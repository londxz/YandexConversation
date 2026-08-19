// Created by Rodion Kholodov.

package whisper

import (
	"context"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"

	speechprovider "github.com/londxz/HackatonYandex/backend/internal/speech"
)

func TestClientSendsValidatedWAVToWhisper(t *testing.T) {
	wav := []byte("RIFF-test-WAVE")
	client := newTestClient(t, func(request *http.Request) (*http.Response, error) {
		if request.Method != http.MethodPost {
			t.Fatalf("method = %s, want POST", request.Method)
		}
		if err := request.ParseMultipartForm(1 << 20); err != nil {
			t.Fatalf("ParseMultipartForm() error = %v", err)
		}
		file, _, err := request.FormFile("file")
		if err != nil {
			t.Fatalf("FormFile() error = %v", err)
		}
		defer file.Close()
		receivedWAV, err := io.ReadAll(file)
		if err != nil {
			t.Fatalf("ReadAll() error = %v", err)
		}
		if string(receivedWAV) != string(wav) {
			t.Fatalf("WAV = %q, want %q", receivedWAV, wav)
		}
		if language := request.FormValue("language"); language != "ru" {
			t.Fatalf("language = %q, want ru", language)
		}
		if format := request.FormValue("response_format"); format != "json" {
			t.Fatalf("response_format = %q, want json", format)
		}
		return testResponse(http.StatusOK, `{"text":"  Добрый день  "}`), nil
	})
	result, err := client.Transcribe(context.Background(), speechprovider.RecognitionRequest{
		WAV:      wav,
		Language: "ru-RU",
	})
	if err != nil {
		t.Fatalf("Transcribe() error = %v", err)
	}
	if result.Text != "Добрый день" {
		t.Fatalf("text = %q", result.Text)
	}
}

func TestClientMapsWhisperStatusCodes(t *testing.T) {
	tests := []struct {
		name        string
		statusCode  int
		expectedErr error
	}{
		{name: "bad audio", statusCode: http.StatusBadRequest, expectedErr: speechprovider.ErrRejected},
		{name: "unauthorized", statusCode: http.StatusUnauthorized, expectedErr: speechprovider.ErrUnauthorized},
		{name: "busy", statusCode: http.StatusTooManyRequests, expectedErr: speechprovider.ErrUnavailable},
		{name: "server failure", statusCode: http.StatusInternalServerError, expectedErr: speechprovider.ErrUnavailable},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			client := newTestClient(t, func(_ *http.Request) (*http.Response, error) {
				return testResponse(test.statusCode, ""), nil
			})
			_, err := client.Transcribe(context.Background(), speechprovider.RecognitionRequest{WAV: []byte("wav")})
			if !errors.Is(err, test.expectedErr) {
				t.Fatalf("error = %v, want %v", err, test.expectedErr)
			}
		})
	}
}

func TestClientRejectsInvalidResponse(t *testing.T) {
	client := newTestClient(t, func(_ *http.Request) (*http.Response, error) {
		return testResponse(http.StatusOK, "not-json"), nil
	})
	_, err := client.Transcribe(context.Background(), speechprovider.RecognitionRequest{WAV: []byte("wav")})
	if !errors.Is(err, speechprovider.ErrUnavailable) {
		t.Fatalf("error = %v, want ErrUnavailable", err)
	}
}

func TestClientRejectsOversizedResponse(t *testing.T) {
	client := newTestClient(t, func(_ *http.Request) (*http.Response, error) {
		return testResponse(http.StatusOK, strings.Repeat("x", maxResponseBytes+1)), nil
	})
	_, err := client.Transcribe(context.Background(), speechprovider.RecognitionRequest{WAV: []byte("wav")})
	if !errors.Is(err, speechprovider.ErrUnavailable) {
		t.Fatalf("error = %v, want ErrUnavailable", err)
	}
}

func TestNewClientRejectsInvalidConfiguration(t *testing.T) {
	if _, err := NewClient("whisper:8080", http.DefaultClient); err == nil {
		t.Fatal("NewClient() error = nil, want invalid endpoint error")
	}
	if _, err := NewClient("http://whisper:8080/inference", nil); err == nil {
		t.Fatal("NewClient() error = nil, want missing HTTP client error")
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (function roundTripFunc) RoundTrip(request *http.Request) (*http.Response, error) {
	return function(request)
}

func newTestClient(t *testing.T, transport roundTripFunc) *Client {
	t.Helper()
	client, err := NewClient("http://whisper:8080/inference", &http.Client{Transport: transport})
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	return client
}

func testResponse(statusCode int, body string) *http.Response {
	return &http.Response{
		StatusCode: statusCode,
		Header:     make(http.Header),
		Body:       io.NopCloser(strings.NewReader(body)),
	}
}
