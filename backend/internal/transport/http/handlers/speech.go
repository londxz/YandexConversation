// Created by Rodion Kholodov.

package handlers

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"strings"

	"github.com/londxz/HackatonYandex/backend/internal/domain"
	"github.com/londxz/HackatonYandex/backend/internal/security"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/requestctx"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/respond"
	speechusecase "github.com/londxz/HackatonYandex/backend/internal/usecase/speech"
)

const (
	maxSpeechTextFieldBytes = 128
	multipartOverheadBytes  = 64 << 10
)

var (
	errInvalidMultipart = errors.New("multipart request is invalid")
	errSpeechPartLarge  = errors.New("multipart field is too large")
)

type SpeechService interface {
	Transcribe(context.Context, speechusecase.TranscribeInput) (domain.SpeechTranscript, error)
}

type SpeechHandler struct {
	service           SpeechService
	logger            *slog.Logger
	maxWAVUploadBytes int64
}

type speechTranscriptionResponse struct {
	Text       string   `json:"text"`
	Language   string   `json:"language"`
	DurationMS int64    `json:"duration_ms"`
	Confidence *float64 `json:"confidence,omitempty"`
}

func NewSpeechHandler(
	service SpeechService,
	logger *slog.Logger,
	maxAudioBytes int64,
) *SpeechHandler {
	return &SpeechHandler{
		service:           service,
		logger:            logger,
		maxWAVUploadBytes: maxAudioBytes + multipartOverheadBytes,
	}
}

func (handler *SpeechHandler) Transcribe(w http.ResponseWriter, r *http.Request) {
	input, err := handler.decodeTranscriptionRequest(r)
	if err != nil {
		handler.writeRequestError(w, r, err)
		return
	}

	transcript, err := handler.service.Transcribe(r.Context(), input)
	if err != nil {
		handler.writeServiceError(w, r, err)
		return
	}

	respond.JSON(w, http.StatusOK, speechTranscriptionResponse{
		Text:       transcript.Text,
		Language:   transcript.Language,
		DurationMS: transcript.Duration.Milliseconds(),
		Confidence: transcript.Confidence,
	})
}

func (handler *SpeechHandler) decodeTranscriptionRequest(
	r *http.Request,
) (speechusecase.TranscribeInput, error) {
	reader, err := r.MultipartReader()
	if err != nil {
		return speechusecase.TranscribeInput{}, errUnsupportedMediaType
	}

	var input speechusecase.TranscribeInput
	var conversationID string
	seenFields := make(map[string]bool, 3)
	for {
		part, err := reader.NextPart()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return speechusecase.TranscribeInput{}, fmt.Errorf("%w: %w", errInvalidMultipart, err)
		}

		name := part.FormName()
		if seenFields[name] || name == "" {
			_ = part.Close()
			return speechusecase.TranscribeInput{}, errInvalidMultipart
		}
		seenFields[name] = true

		switch name {
		case "file":
			input.WAV, err = readMultipartPart(part, handler.maxWAVUploadBytes)
		case "language":
			var value []byte
			value, err = readMultipartPart(part, maxSpeechTextFieldBytes)
			input.Language = strings.TrimSpace(string(value))
		case "conversation_id":
			var value []byte
			value, err = readMultipartPart(part, maxSpeechTextFieldBytes)
			conversationID = strings.TrimSpace(string(value))
		default:
			_ = part.Close()
			return speechusecase.TranscribeInput{}, errInvalidMultipart
		}
		_ = part.Close()
		if err != nil {
			return speechusecase.TranscribeInput{}, err
		}
	}

	if len(input.WAV) == 0 || input.Language == "" {
		return speechusecase.TranscribeInput{}, errInvalidMultipart
	}
	if conversationID != "" && !security.IsUUID(conversationID) {
		return speechusecase.TranscribeInput{}, errInvalidMultipart
	}
	return input, nil
}

func readMultipartPart(part *multipart.Part, limit int64) ([]byte, error) {
	data, err := io.ReadAll(io.LimitReader(part, limit+1))
	if err != nil {
		return nil, fmt.Errorf("%w: %w", errInvalidMultipart, err)
	}
	if int64(len(data)) > limit {
		return nil, errSpeechPartLarge
	}
	return data, nil
}

func (handler *SpeechHandler) writeRequestError(w http.ResponseWriter, r *http.Request, err error) {
	var maxBytesError *http.MaxBytesError
	switch {
	case errors.Is(err, errUnsupportedMediaType):
		respond.Error(w, r, http.StatusUnsupportedMediaType, "unsupported_media_type", "Content-Type must be multipart/form-data.")
	case errors.Is(err, errSpeechPartLarge), errors.As(err, &maxBytesError):
		respond.Error(w, r, http.StatusRequestEntityTooLarge, "audio_too_large", "Audio file is too large.")
	default:
		respond.Error(w, r, http.StatusBadRequest, "invalid_request", "Multipart request is invalid.")
	}
}

func (handler *SpeechHandler) writeServiceError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, domain.ErrInvalidAudio):
		respond.Error(w, r, http.StatusUnprocessableEntity, "invalid_audio", "Audio must be PCM16, 16 kHz, mono WAV.")
	case errors.Is(err, domain.ErrAudioTooLarge):
		respond.Error(w, r, http.StatusRequestEntityTooLarge, "audio_too_large", "Audio file is too large.")
	case errors.Is(err, domain.ErrAudioTooLong):
		respond.Error(w, r, http.StatusUnprocessableEntity, "audio_too_long", "Audio duration exceeds the supported limit.")
	case errors.Is(err, domain.ErrUnsupportedLanguage):
		respond.Error(w, r, http.StatusUnprocessableEntity, "unsupported_language", "Recognition language is unsupported.")
	case errors.Is(err, domain.ErrSpeechTimeout):
		respond.Error(w, r, http.StatusGatewayTimeout, "speech_timeout", "Speech recognition timed out.")
	case errors.Is(err, domain.ErrSpeechBusy):
		w.Header().Set("Retry-After", "1")
		respond.Error(w, r, http.StatusTooManyRequests, "speech_busy", "Speech recognition is busy. Try again shortly.")
	case errors.Is(err, domain.ErrSpeechProvider):
		respond.Error(w, r, http.StatusBadGateway, "speech_provider_error", "Speech provider rejected the request.")
	case errors.Is(err, domain.ErrSpeechUnavailable):
		respond.Error(w, r, http.StatusServiceUnavailable, "speech_unavailable", "Speech recognition is temporarily unavailable.")
	default:
		handler.logger.ErrorContext(
			r.Context(),
			"speech transcription failed",
			"request_id", requestctx.RequestID(r.Context()),
			"error", err,
		)
		respond.Error(w, r, http.StatusInternalServerError, "internal_error", "An internal error occurred.")
	}
}
