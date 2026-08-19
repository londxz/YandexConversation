// Created by Rodion Kholodov.

package handlers

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/londxz/HackatonYandex/backend/internal/domain"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/respond"
	speechusecase "github.com/londxz/HackatonYandex/backend/internal/usecase/speech"
)

type speechServiceStub struct {
	transcript domain.SpeechTranscript
	err        error
	input      speechusecase.TranscribeInput
	callCount  int
}

func (stub *speechServiceStub) Transcribe(
	_ context.Context,
	input speechusecase.TranscribeInput,
) (domain.SpeechTranscript, error) {
	stub.callCount++
	stub.input = input
	return stub.transcript, stub.err
}

func TestSpeechHandlerReturnsTranscriptionContract(t *testing.T) {
	confidence := 0.92
	service := &speechServiceStub{transcript: domain.SpeechTranscript{
		Text:       "Здравствуйте",
		Language:   "ru-RU",
		Duration:   1250 * time.Millisecond,
		Confidence: &confidence,
	}}
	handler := NewSpeechHandler(service, speechHandlerTestLogger(), 1<<20)
	request := newSpeechMultipartRequest(t, makeHandlerTestWAV(), map[string]string{
		"language":        "ru-RU",
		"conversation_id": "72ab9284-7b7e-4f47-99b9-f7b682b2c718",
	})
	recorder := httptest.NewRecorder()

	handler.Transcribe(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200; body = %s", recorder.Code, recorder.Body.String())
	}
	if service.callCount != 1 {
		t.Fatalf("service calls = %d, want 1", service.callCount)
	}
	if service.input.Language != "ru-RU" || len(service.input.WAV) == 0 {
		t.Fatalf("service input = %#v", service.input)
	}

	var response struct {
		Text       string  `json:"text"`
		Language   string  `json:"language"`
		DurationMS int64   `json:"duration_ms"`
		Confidence float64 `json:"confidence"`
	}
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if response.Text != "Здравствуйте" || response.Language != "ru-RU" {
		t.Fatalf("response = %#v", response)
	}
	if response.DurationMS != 1250 || response.Confidence != confidence {
		t.Fatalf("response metadata = %#v", response)
	}
}

func TestSpeechHandlerRejectsInvalidMultipartWithoutCallingService(t *testing.T) {
	tests := []struct {
		name       string
		request    func(*testing.T) *http.Request
		statusCode int
		errorCode  string
	}{
		{
			name: "wrong content type",
			request: func(*testing.T) *http.Request {
				request := httptest.NewRequest(http.MethodPost, "/v1/speech/transcribe", bytes.NewReader(nil))
				request.Header.Set("Content-Type", "application/json")
				return request
			},
			statusCode: http.StatusUnsupportedMediaType,
			errorCode:  "unsupported_media_type",
		},
		{
			name: "missing language",
			request: func(t *testing.T) *http.Request {
				return newSpeechMultipartRequest(t, makeHandlerTestWAV(), nil)
			},
			statusCode: http.StatusBadRequest,
			errorCode:  "invalid_request",
		},
		{
			name: "invalid conversation ID",
			request: func(t *testing.T) *http.Request {
				return newSpeechMultipartRequest(t, makeHandlerTestWAV(), map[string]string{
					"language":        "ru-RU",
					"conversation_id": "not-a-uuid",
				})
			},
			statusCode: http.StatusBadRequest,
			errorCode:  "invalid_request",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := &speechServiceStub{}
			handler := NewSpeechHandler(service, speechHandlerTestLogger(), 1<<20)
			recorder := httptest.NewRecorder()
			handler.Transcribe(recorder, test.request(t))
			if recorder.Code != test.statusCode {
				t.Fatalf("status = %d, want %d", recorder.Code, test.statusCode)
			}
			if service.callCount != 0 {
				t.Fatalf("service calls = %d, want 0", service.callCount)
			}
			assertSpeechErrorCode(t, recorder, test.errorCode)
		})
	}
}

func TestSpeechHandlerMapsServiceErrors(t *testing.T) {
	tests := []struct {
		name       string
		err        error
		statusCode int
		errorCode  string
	}{
		{name: "invalid audio", err: domain.ErrInvalidAudio, statusCode: 422, errorCode: "invalid_audio"},
		{name: "too large", err: domain.ErrAudioTooLarge, statusCode: 413, errorCode: "audio_too_large"},
		{name: "too long", err: domain.ErrAudioTooLong, statusCode: 422, errorCode: "audio_too_long"},
		{name: "language", err: domain.ErrUnsupportedLanguage, statusCode: 422, errorCode: "unsupported_language"},
		{name: "timeout", err: domain.ErrSpeechTimeout, statusCode: 504, errorCode: "speech_timeout"},
		{name: "busy", err: domain.ErrSpeechBusy, statusCode: 429, errorCode: "speech_busy"},
		{name: "provider", err: domain.ErrSpeechProvider, statusCode: 502, errorCode: "speech_provider_error"},
		{name: "unavailable", err: domain.ErrSpeechUnavailable, statusCode: 503, errorCode: "speech_unavailable"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := &speechServiceStub{err: test.err}
			handler := NewSpeechHandler(service, speechHandlerTestLogger(), 1<<20)
			request := newSpeechMultipartRequest(t, makeHandlerTestWAV(), map[string]string{"language": "ru-RU"})
			recorder := httptest.NewRecorder()
			handler.Transcribe(recorder, request)
			if recorder.Code != test.statusCode {
				t.Fatalf("status = %d, want %d", recorder.Code, test.statusCode)
			}
			if errors.Is(test.err, domain.ErrSpeechBusy) && recorder.Header().Get("Retry-After") != "1" {
				t.Fatalf("Retry-After = %q, want 1", recorder.Header().Get("Retry-After"))
			}
			assertSpeechErrorCode(t, recorder, test.errorCode)
		})
	}
}

func TestSpeechHandlerRejectsOversizedFilePart(t *testing.T) {
	service := &speechServiceStub{}
	handler := NewSpeechHandler(service, speechHandlerTestLogger(), 1)
	oversizedWAV := make([]byte, multipartOverheadBytes+2)
	request := newSpeechMultipartRequest(t, oversizedWAV, map[string]string{"language": "ru-RU"})
	recorder := httptest.NewRecorder()

	handler.Transcribe(recorder, request)

	if recorder.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusRequestEntityTooLarge)
	}
	if service.callCount != 0 {
		t.Fatalf("service calls = %d, want 0", service.callCount)
	}
	assertSpeechErrorCode(t, recorder, "audio_too_large")
}

func newSpeechMultipartRequest(
	t *testing.T,
	wav []byte,
	fields map[string]string,
) *http.Request {
	t.Helper()
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	for name, value := range fields {
		if err := writer.WriteField(name, value); err != nil {
			t.Fatalf("write field: %v", err)
		}
	}
	if wav != nil {
		part, err := writer.CreateFormFile("file", "recording.wav")
		if err != nil {
			t.Fatalf("create file part: %v", err)
		}
		if _, err := part.Write(wav); err != nil {
			t.Fatalf("write WAV: %v", err)
		}
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close multipart writer: %v", err)
	}

	request := httptest.NewRequest(http.MethodPost, "/v1/speech/transcribe", &body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	return request
}

func makeHandlerTestWAV() []byte {
	pcm := make([]byte, 3200)
	data := make([]byte, 44+len(pcm))
	copy(data[0:4], "RIFF")
	binary.LittleEndian.PutUint32(data[4:8], uint32(len(data)-8))
	copy(data[8:12], "WAVE")
	copy(data[12:16], "fmt ")
	binary.LittleEndian.PutUint32(data[16:20], 16)
	binary.LittleEndian.PutUint16(data[20:22], 1)
	binary.LittleEndian.PutUint16(data[22:24], 1)
	binary.LittleEndian.PutUint32(data[24:28], 16000)
	binary.LittleEndian.PutUint32(data[28:32], 32000)
	binary.LittleEndian.PutUint16(data[32:34], 2)
	binary.LittleEndian.PutUint16(data[34:36], 16)
	copy(data[36:40], "data")
	binary.LittleEndian.PutUint32(data[40:44], uint32(len(pcm)))
	copy(data[44:], pcm)
	return data
}

func assertSpeechErrorCode(t *testing.T, recorder *httptest.ResponseRecorder, expected string) {
	t.Helper()
	var envelope respond.ErrorEnvelope
	if err := json.NewDecoder(recorder.Body).Decode(&envelope); err != nil {
		t.Fatalf("decode error response: %v", err)
	}
	if envelope.Error.Code != expected {
		t.Fatalf("error code = %q, want %q", envelope.Error.Code, expected)
	}
}

func speechHandlerTestLogger() *slog.Logger {
	return slog.New(slog.NewJSONHandler(io.Discard, nil))
}
