// Created by Rodion Kholodov.

package wstransport

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"io"
	"log/slog"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/londxz/HackatonYandex/backend/internal/domain"
	speakerprovider "github.com/londxz/HackatonYandex/backend/internal/speaker"
	diarizationusecase "github.com/londxz/HackatonYandex/backend/internal/usecase/diarization"
	speechusecase "github.com/londxz/HackatonYandex/backend/internal/usecase/speech"
)

func TestSpeechStreamReturnsPartialFinalAndStoppedEvents(t *testing.T) {
	service := &streamSpeechService{text: "распознанная речь"}
	handler := newTestSpeechStreamHandler(service)
	server := httptest.NewServer(handler)
	defer server.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	connection, _, err := websocket.Dial(ctx, websocketURL(server.URL), nil)
	if err != nil {
		t.Fatalf("websocket.Dial() error = %v", err)
	}
	defer connection.CloseNow()

	writeTestJSON(t, ctx, connection, validStartMessage())
	if event := readTestEvent(t, ctx, connection); event.Type != "ready" {
		t.Fatalf("first event type = %q, want ready", event.Type)
	}

	writeTestJSON(t, ctx, connection, clientAudioChunk{
		Type:     "audio_chunk",
		Sequence: 1,
		Data:     pcmChunk(2000, 1600),
	})
	writeTestJSON(t, ctx, connection, clientAudioChunk{
		Type:     "audio_chunk",
		Sequence: 2,
		Data:     pcmChunk(0, 1600),
	})

	var final serverEvent
	for final.Type != "final" {
		final = readTestEvent(t, ctx, connection)
		if final.Type != "partial" && final.Type != "final" {
			t.Fatalf("speech event type = %q, want partial or final", final.Type)
		}
	}
	if final.Text != service.text {
		t.Fatalf("final text = %q, want %q", final.Text, service.text)
	}
	if final.MessageID == "" || final.Speaker == nil || final.Speaker.Label != "Говорящий 1" {
		t.Fatalf("final event is incomplete: %#v", final)
	}

	writeTestJSON(t, ctx, connection, map[string]string{"type": "stop"})
	if event := readTestEvent(t, ctx, connection); event.Type != "stopped" {
		t.Fatalf("last event type = %q, want stopped", event.Type)
	}
	if service.callCount() < 1 {
		t.Fatal("speech service was not called")
	}
	if wav := service.lastWAV(); len(wav) < 44 || string(wav[:4]) != "RIFF" {
		t.Fatal("stream audio was not converted to WAV")
	}
}

func TestSpeechStreamRejectsOutOfOrderAudioChunk(t *testing.T) {
	handler := newTestSpeechStreamHandler(&streamSpeechService{text: "unused"})
	server := httptest.NewServer(handler)
	defer server.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	connection, _, err := websocket.Dial(ctx, websocketURL(server.URL), nil)
	if err != nil {
		t.Fatalf("websocket.Dial() error = %v", err)
	}
	defer connection.CloseNow()

	writeTestJSON(t, ctx, connection, validStartMessage())
	_ = readTestEvent(t, ctx, connection)
	writeTestJSON(t, ctx, connection, clientAudioChunk{
		Type:     "audio_chunk",
		Sequence: 2,
		Data:     pcmChunk(2000, 1600),
	})

	event := readTestEvent(t, ctx, connection)
	if event.Type != "error" || event.Code != "invalid_sequence" {
		t.Fatalf("event = %#v, want invalid_sequence error", event)
	}
}

func TestSpeechStreamAssignsDifferentStableSpeakers(t *testing.T) {
	service := &streamSpeechService{text: "реплика"}
	embedder := &streamEmbeddingProvider{vectors: [][]float32{{1, 0}, {0, 1}, {0.99, 0.01}}}
	handler := newTestSpeechStreamHandlerWithEmbedder(service, embedder)
	server := httptest.NewServer(handler)
	defer server.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	connection, _, err := websocket.Dial(ctx, websocketURL(server.URL), nil)
	if err != nil {
		t.Fatalf("websocket.Dial() error = %v", err)
	}
	defer connection.CloseNow()

	writeTestJSON(t, ctx, connection, validStartMessage())
	_ = readTestEvent(t, ctx, connection)

	first := sendTestSegment(t, ctx, connection, 1)
	second := sendTestSegment(t, ctx, connection, 3)
	third := sendTestSegment(t, ctx, connection, 5)

	if first.Speaker == nil || first.Speaker.ID != "speaker_1" {
		t.Fatalf("first speaker = %#v", first.Speaker)
	}
	if second.Speaker == nil || second.Speaker.ID != "speaker_2" {
		t.Fatalf("second speaker = %#v", second.Speaker)
	}
	if third.Speaker == nil || third.Speaker.ID != "speaker_1" {
		t.Fatalf("third speaker = %#v", third.Speaker)
	}
}

type streamSpeechService struct {
	mu    sync.Mutex
	text  string
	calls [][]byte
}

type streamEmbeddingProvider struct {
	mu      sync.Mutex
	vectors [][]float32
	calls   int
}

func (provider *streamEmbeddingProvider) Embed(
	context.Context,
	speakerprovider.EmbeddingRequest,
) (speakerprovider.EmbeddingResult, error) {
	provider.mu.Lock()
	defer provider.mu.Unlock()
	vector := provider.vectors[provider.calls]
	provider.calls++
	return speakerprovider.EmbeddingResult{Vector: vector}, nil
}

func (service *streamSpeechService) Transcribe(
	_ context.Context,
	input speechusecase.TranscribeInput,
) (domain.SpeechTranscript, error) {
	service.mu.Lock()
	service.calls = append(service.calls, append([]byte(nil), input.WAV...))
	service.mu.Unlock()
	return domain.SpeechTranscript{
		Text:     service.text,
		Language: input.Language,
		Duration: 100 * time.Millisecond,
	}, nil
}

func (service *streamSpeechService) callCount() int {
	service.mu.Lock()
	defer service.mu.Unlock()
	return len(service.calls)
}

func (service *streamSpeechService) lastWAV() []byte {
	service.mu.Lock()
	defer service.mu.Unlock()
	if len(service.calls) == 0 {
		return nil
	}
	return append([]byte(nil), service.calls[len(service.calls)-1]...)
}

func newTestSpeechStreamHandler(service SpeechService) *SpeechStreamHandler {
	return newTestSpeechStreamHandlerWithEmbedder(
		service,
		&streamEmbeddingProvider{vectors: [][]float32{{1, 0}, {1, 0}, {1, 0}, {1, 0}}},
	)
}

func newTestSpeechStreamHandlerWithEmbedder(
	service SpeechService,
	embedder speakerprovider.Provider,
) *SpeechStreamHandler {
	diarizationService := diarizationusecase.NewService(embedder, diarizationusecase.Policy{
		EmbeddingTimeout:    time.Second,
		MinimumAudio:        50 * time.Millisecond,
		SimilarityThreshold: 0.75,
		MaximumSpeakers:     8,
		MaxConcurrent:       2,
	})
	return NewSpeechStreamHandler(
		service,
		diarizationService,
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		SpeechStreamPolicy{
			PartialInterval:    100 * time.Millisecond,
			SilenceDuration:    100 * time.Millisecond,
			MaxSegmentDuration: 2 * time.Second,
			MaxChunkBytes:      8 << 10,
			MaxConnections:     2,
		},
	)
}

func sendTestSegment(
	t *testing.T,
	ctx context.Context,
	connection *websocket.Conn,
	firstSequence int64,
) serverEvent {
	t.Helper()
	writeTestJSON(t, ctx, connection, clientAudioChunk{
		Type:     "audio_chunk",
		Sequence: firstSequence,
		Data:     pcmChunk(2000, 1600),
	})
	writeTestJSON(t, ctx, connection, clientAudioChunk{
		Type:     "audio_chunk",
		Sequence: firstSequence + 1,
		Data:     pcmChunk(0, 1600),
	})
	for {
		event := readTestEvent(t, ctx, connection)
		if event.Type == "final" {
			return event
		}
		if event.Type != "partial" {
			t.Fatalf("speech event type = %q, want partial or final", event.Type)
		}
	}
}

func validStartMessage() clientStart {
	return clientStart{
		Type:           "start",
		ConversationID: "5bdb3e0c-4f6a-4eec-8ddd-74f0e98782e5",
		Mode:           "listen",
		Language:       "ru-RU",
		Audio: audioFormat{
			Format:     "pcm16",
			SampleRate: requiredSampleRate,
			Channels:   requiredChannels,
		},
	}
}

func websocketURL(httpURL string) string {
	return "ws" + strings.TrimPrefix(httpURL, "http")
}

func writeTestJSON(t *testing.T, ctx context.Context, connection *websocket.Conn, value any) {
	t.Helper()
	payload, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("json.Marshal() error = %v", err)
	}
	if err := connection.Write(ctx, websocket.MessageText, payload); err != nil {
		t.Fatalf("connection.Write() error = %v", err)
	}
}

func readTestEvent(t *testing.T, ctx context.Context, connection *websocket.Conn) serverEvent {
	t.Helper()
	messageType, payload, err := connection.Read(ctx)
	if err != nil {
		t.Fatalf("connection.Read() error = %v", err)
	}
	if messageType != websocket.MessageText {
		t.Fatalf("message type = %v, want text", messageType)
	}
	var event serverEvent
	if err := json.Unmarshal(payload, &event); err != nil {
		t.Fatalf("json.Unmarshal() error = %v", err)
	}
	return event
}

func pcmChunk(value int16, samples int) []byte {
	pcm := make([]byte, samples*2)
	for offset := 0; offset < len(pcm); offset += 2 {
		binary.LittleEndian.PutUint16(pcm[offset:offset+2], uint16(value))
	}
	return pcm
}
