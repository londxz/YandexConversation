// Created by Rodion Kholodov.

package wstransport

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/londxz/HackatonYandex/backend/internal/domain"
	"github.com/londxz/HackatonYandex/backend/internal/security"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/requestctx"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/respond"
	speechusecase "github.com/londxz/HackatonYandex/backend/internal/usecase/speech"
)

const (
	requiredSampleRate = 16000
	requiredChannels   = 1
	pcmBytesPerSecond  = requiredSampleRate * requiredChannels * 2
	silenceThreshold   = 420
	startTimeout       = 10 * time.Second
)

type SpeechService interface {
	Transcribe(context.Context, speechusecase.TranscribeInput) (domain.SpeechTranscript, error)
}

type SpeechStreamPolicy struct {
	PartialInterval    time.Duration
	SilenceDuration    time.Duration
	MaxSegmentDuration time.Duration
	MaxChunkBytes      int64
	MaxConnections     int
}

type SpeechStreamHandler struct {
	service SpeechService
	logger  *slog.Logger
	policy  SpeechStreamPolicy
	slots   chan struct{}

	connectionsMu sync.Mutex
	connections   map[*websocket.Conn]struct{}
}

type clientEnvelope struct {
	Type string `json:"type"`
}

type clientStart struct {
	Type           string      `json:"type"`
	ConversationID string      `json:"conversation_id"`
	Mode           string      `json:"mode"`
	Language       string      `json:"language"`
	Audio          audioFormat `json:"audio"`
}

type audioFormat struct {
	Format     string `json:"format"`
	SampleRate int    `json:"sample_rate"`
	Channels   int    `json:"channels"`
}

type clientAudioChunk struct {
	Type     string `json:"type"`
	Sequence int64  `json:"sequence"`
	Data     []byte `json:"data"`
}

type clientMessage struct {
	typeName string
	chunk    clientAudioChunk
}

type serverEvent struct {
	Type       string   `json:"type"`
	Sequence   int64    `json:"sequence,omitempty"`
	MessageID  string   `json:"message_id,omitempty"`
	Text       string   `json:"text,omitempty"`
	Speaker    *speaker `json:"speaker,omitempty"`
	Confidence *float64 `json:"confidence,omitempty"`
	StartedAt  string   `json:"started_at,omitempty"`
	EndedAt    string   `json:"ended_at,omitempty"`
	Code       string   `json:"code,omitempty"`
	Message    string   `json:"message,omitempty"`
	RequestID  string   `json:"request_id,omitempty"`
}

type speaker struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

type protocolError struct {
	code    string
	message string
	status  websocket.StatusCode
}

func (err protocolError) Error() string {
	return err.code
}

type recognitionJob struct {
	pcm       []byte
	final     bool
	startedAt time.Time
	endedAt   time.Time
}

type recognitionResult struct {
	job        recognitionJob
	transcript domain.SpeechTranscript
	err        error
}

func NewSpeechStreamHandler(
	service SpeechService,
	logger *slog.Logger,
	policy SpeechStreamPolicy,
) *SpeechStreamHandler {
	return &SpeechStreamHandler{
		service:     service,
		logger:      logger,
		policy:      policy,
		slots:       make(chan struct{}, policy.MaxConnections),
		connections: make(map[*websocket.Conn]struct{}),
	}
}

func (handler *SpeechStreamHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	select {
	case handler.slots <- struct{}{}:
		defer func() { <-handler.slots }()
	default:
		respond.Error(w, r, http.StatusServiceUnavailable, "speech_busy", "Speech streaming is busy. Try again shortly.")
		return
	}

	connection, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		CompressionMode: websocket.CompressionDisabled,
	})
	if err != nil {
		return
	}
	handler.register(connection)
	defer handler.unregister(connection)
	defer connection.CloseNow()

	maxMessageBytes := handler.policy.MaxChunkBytes*2 + 4096
	connection.SetReadLimit(maxMessageBytes)

	if err := handler.runSession(r.Context(), connection); err != nil {
		var clientError protocolError
		if errors.As(err, &clientError) {
			handler.writeError(r.Context(), connection, clientError.code, clientError.message)
			_ = connection.Close(clientError.status, clientError.message)
			return
		}

		status := websocket.CloseStatus(err)
		if status == websocket.StatusNormalClosure || status == websocket.StatusGoingAway {
			return
		}
		handler.logger.WarnContext(
			r.Context(),
			"speech stream closed",
			"request_id", requestctx.RequestID(r.Context()),
			"error", err,
		)
	}
}

func (handler *SpeechStreamHandler) Shutdown(ctx context.Context) {
	handler.connectionsMu.Lock()
	connections := make([]*websocket.Conn, 0, len(handler.connections))
	for connection := range handler.connections {
		connections = append(connections, connection)
	}
	handler.connectionsMu.Unlock()

	for _, connection := range connections {
		select {
		case <-ctx.Done():
			connection.CloseNow()
		default:
			_ = connection.Close(websocket.StatusGoingAway, "server shutdown")
		}
	}
}

func (handler *SpeechStreamHandler) runSession(
	ctx context.Context,
	connection *websocket.Conn,
) error {
	startContext, cancelStart := context.WithTimeout(ctx, startTimeout)
	start, err := handler.readStart(startContext, connection)
	cancelStart()
	if err != nil {
		return err
	}

	if err := writeJSON(ctx, connection, serverEvent{Type: "ready"}); err != nil {
		return err
	}

	messages := make(chan clientMessage, 64)
	readErrors := make(chan error, 1)
	go handler.readMessages(ctx, connection, messages, readErrors)

	return handler.processMessages(ctx, connection, start, messages, readErrors)
}

func (handler *SpeechStreamHandler) readStart(
	ctx context.Context,
	connection *websocket.Conn,
) (clientStart, error) {
	messageType, payload, err := connection.Read(ctx)
	if err != nil {
		return clientStart{}, err
	}
	if messageType != websocket.MessageText {
		return clientStart{}, newProtocolError("unsupported_message", "Messages must be JSON text.")
	}

	var start clientStart
	if err := json.Unmarshal(payload, &start); err != nil {
		return clientStart{}, newProtocolError("invalid_message", "Start message is invalid.")
	}
	if start.Type != "start" || !security.IsUUID(start.ConversationID) {
		return clientStart{}, newProtocolError("invalid_start", "A valid start message is required.")
	}
	if start.Mode != "listen" || strings.TrimSpace(start.Language) == "" {
		return clientStart{}, newProtocolError("invalid_start", "Listen mode and language are required.")
	}
	if start.Audio.Format != "pcm16" ||
		start.Audio.SampleRate != requiredSampleRate ||
		start.Audio.Channels != requiredChannels {
		return clientStart{}, newProtocolError("unsupported_audio", "Audio must be PCM16, 16 kHz, mono.")
	}
	return start, nil
}

func (handler *SpeechStreamHandler) readMessages(
	ctx context.Context,
	connection *websocket.Conn,
	messages chan<- clientMessage,
	errorsChannel chan<- error,
) {
	for {
		messageType, payload, err := connection.Read(ctx)
		if err != nil {
			errorsChannel <- err
			return
		}
		if messageType != websocket.MessageText {
			errorsChannel <- newProtocolError("unsupported_message", "Messages must be JSON text.")
			return
		}

		var envelope clientEnvelope
		if err := json.Unmarshal(payload, &envelope); err != nil {
			errorsChannel <- newProtocolError("invalid_message", "Message is invalid.")
			return
		}

		switch envelope.Type {
		case "audio_chunk":
			var chunk clientAudioChunk
			if err := json.Unmarshal(payload, &chunk); err != nil {
				errorsChannel <- newProtocolError("invalid_audio_chunk", "Audio chunk is invalid.")
				return
			}
			select {
			case messages <- clientMessage{typeName: envelope.Type, chunk: chunk}:
			case <-ctx.Done():
				return
			}
		case "stop":
			select {
			case messages <- clientMessage{typeName: envelope.Type}:
			case <-ctx.Done():
			}
			return
		default:
			errorsChannel <- newProtocolError("unsupported_message", "Message type is unsupported.")
			return
		}
	}
}

func (handler *SpeechStreamHandler) processMessages(
	ctx context.Context,
	connection *websocket.Conn,
	start clientStart,
	messages <-chan clientMessage,
	readErrors <-chan error,
) error {
	partialBytes := durationBytes(handler.policy.PartialInterval)
	silenceBytes := durationBytes(handler.policy.SilenceDuration)
	maxSegmentBytes := durationBytes(handler.policy.MaxSegmentDuration)
	results := make(chan recognitionResult, 1)

	var segment []byte
	var segmentStartedAt time.Time
	var trailingSilence int
	var lastPartialBytes int
	var expectedClientSequence int64 = 1
	var serverSequence int64
	var inFlight bool
	var pendingPartial *recognitionJob
	var pendingFinals []recognitionJob
	var stopping bool

	startRecognition := func(job recognitionJob) {
		inFlight = true
		go func() {
			transcript, err := handler.service.Transcribe(ctx, speechusecase.TranscribeInput{
				WAV:      pcm16WAV(job.pcm),
				Language: start.Language,
			})
			select {
			case results <- recognitionResult{job: job, transcript: transcript, err: err}:
			case <-ctx.Done():
			}
		}()
	}

	scheduleRecognition := func(job recognitionJob) {
		if job.final {
			pendingPartial = nil
		}
		if !inFlight {
			startRecognition(job)
			return
		}
		if job.final {
			pendingFinals = append(pendingFinals, job)
			return
		}
		pendingPartial = &job
	}

	scheduleFinal := func(endedAt time.Time) {
		if len(segment) == 0 {
			return
		}
		trimmedLength := len(segment) - trailingSilence
		if trimmedLength <= 0 {
			segment = nil
			trailingSilence = 0
			lastPartialBytes = 0
			return
		}
		pcm := append([]byte(nil), segment[:trimmedLength]...)
		scheduleRecognition(recognitionJob{
			pcm:       pcm,
			final:     true,
			startedAt: segmentStartedAt,
			endedAt:   endedAt,
		})
		segment = nil
		trailingSilence = 0
		lastPartialBytes = 0
	}

	for {
		if stopping && !inFlight && len(pendingFinals) == 0 {
			if err := writeJSON(ctx, connection, serverEvent{Type: "stopped"}); err != nil {
				return err
			}
			return connection.Close(websocket.StatusNormalClosure, "")
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case err := <-readErrors:
			return err
		case message := <-messages:
			if message.typeName == "stop" {
				stopping = true
				pendingPartial = nil
				scheduleFinal(time.Now().UTC())
				continue
			}
			if stopping {
				continue
			}
			chunk := message.chunk
			if chunk.Sequence != expectedClientSequence {
				return newProtocolError("invalid_sequence", "Audio chunk sequence is invalid.")
			}
			expectedClientSequence++
			if len(chunk.Data) == 0 || int64(len(chunk.Data)) > handler.policy.MaxChunkBytes || len(chunk.Data)%2 != 0 {
				return newProtocolError("invalid_audio_chunk", "Audio chunk size is invalid.")
			}

			now := time.Now().UTC()
			silent := isSilentPCM16(chunk.Data)
			if len(segment) == 0 {
				if silent {
					continue
				}
				segmentStartedAt = now
			}
			segment = append(segment, chunk.Data...)
			if silent {
				trailingSilence += len(chunk.Data)
			} else {
				trailingSilence = 0
			}

			if trailingSilence >= silenceBytes || len(segment) >= maxSegmentBytes {
				scheduleFinal(now)
				continue
			}
			if len(segment) >= partialBytes && len(segment)-lastPartialBytes >= partialBytes {
				lastPartialBytes = len(segment)
				scheduleRecognition(recognitionJob{
					pcm:       append([]byte(nil), segment...),
					startedAt: segmentStartedAt,
					endedAt:   now,
				})
			}
		case result := <-results:
			inFlight = false
			if result.err != nil {
				if result.job.final {
					code, message := speechError(result.err)
					if err := handler.writeError(ctx, connection, code, message); err != nil {
						return err
					}
				}
			} else if text := strings.TrimSpace(result.transcript.Text); text != "" {
				serverSequence++
				event := serverEvent{
					Type:       "partial",
					Sequence:   serverSequence,
					Text:       text,
					Speaker:    &speaker{ID: "speaker_1", Label: "Говорящий 1"},
					Confidence: result.transcript.Confidence,
				}
				if result.job.final {
					messageID, idErr := security.NewUUID()
					if idErr != nil {
						return fmt.Errorf("generate message id: %w", idErr)
					}
					event.Type = "final"
					event.MessageID = messageID
					event.StartedAt = result.job.startedAt.Format(time.RFC3339Nano)
					event.EndedAt = result.job.endedAt.Format(time.RFC3339Nano)
				}
				if err := writeJSON(ctx, connection, event); err != nil {
					return err
				}
			}

			if len(pendingFinals) > 0 {
				next := pendingFinals[0]
				pendingFinals = pendingFinals[1:]
				startRecognition(next)
			} else if !stopping && pendingPartial != nil {
				next := *pendingPartial
				pendingPartial = nil
				startRecognition(next)
			}
		}
	}
}

func (handler *SpeechStreamHandler) writeError(
	ctx context.Context,
	connection *websocket.Conn,
	code string,
	message string,
) error {
	return writeJSON(ctx, connection, serverEvent{
		Type:      "error",
		Code:      code,
		Message:   message,
		RequestID: requestctx.RequestID(ctx),
	})
}

func (handler *SpeechStreamHandler) register(connection *websocket.Conn) {
	handler.connectionsMu.Lock()
	defer handler.connectionsMu.Unlock()
	handler.connections[connection] = struct{}{}
}

func (handler *SpeechStreamHandler) unregister(connection *websocket.Conn) {
	handler.connectionsMu.Lock()
	defer handler.connectionsMu.Unlock()
	delete(handler.connections, connection)
}

func writeJSON(ctx context.Context, connection *websocket.Conn, value any) error {
	payload, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("encode websocket message: %w", err)
	}
	if err := connection.Write(ctx, websocket.MessageText, payload); err != nil {
		return fmt.Errorf("write websocket message: %w", err)
	}
	return nil
}

func newProtocolError(code string, message string) protocolError {
	return protocolError{
		code:    code,
		message: message,
		status:  websocket.StatusPolicyViolation,
	}
}

func durationBytes(duration time.Duration) int {
	return int(float64(pcmBytesPerSecond) * duration.Seconds())
}

func isSilentPCM16(pcm []byte) bool {
	if len(pcm) < 2 {
		return true
	}
	var absoluteTotal int64
	for offset := 0; offset+1 < len(pcm); offset += 2 {
		sample := int64(int16(binary.LittleEndian.Uint16(pcm[offset : offset+2])))
		if sample < 0 {
			sample = -sample
		}
		absoluteTotal += sample
	}
	samples := int64(len(pcm) / 2)
	return absoluteTotal/samples < silenceThreshold
}

func pcm16WAV(pcm []byte) []byte {
	wav := make([]byte, 44+len(pcm))
	copy(wav[0:4], "RIFF")
	binary.LittleEndian.PutUint32(wav[4:8], uint32(36+len(pcm)))
	copy(wav[8:12], "WAVE")
	copy(wav[12:16], "fmt ")
	binary.LittleEndian.PutUint32(wav[16:20], 16)
	binary.LittleEndian.PutUint16(wav[20:22], 1)
	binary.LittleEndian.PutUint16(wav[22:24], requiredChannels)
	binary.LittleEndian.PutUint32(wav[24:28], requiredSampleRate)
	binary.LittleEndian.PutUint32(wav[28:32], pcmBytesPerSecond)
	binary.LittleEndian.PutUint16(wav[32:34], requiredChannels*2)
	binary.LittleEndian.PutUint16(wav[34:36], 16)
	copy(wav[36:40], "data")
	binary.LittleEndian.PutUint32(wav[40:44], uint32(len(pcm)))
	copy(wav[44:], pcm)
	return wav
}

func speechError(err error) (string, string) {
	switch {
	case errors.Is(err, domain.ErrUnsupportedLanguage):
		return "unsupported_language", "Recognition language is unsupported."
	case errors.Is(err, domain.ErrSpeechBusy):
		return "speech_busy", "Speech recognition is busy."
	case errors.Is(err, domain.ErrSpeechTimeout):
		return "speech_timeout", "Speech recognition timed out."
	default:
		return "speech_unavailable", "Speech recognition is temporarily unavailable."
	}
}
