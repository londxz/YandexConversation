// Created by Rodion Kholodov.

package yandex

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	speechprovider "github.com/londxz/HackatonYandex/backend/internal/speech"
)

func TestClientSendsSpeechKitV1Contract(t *testing.T) {
	pcm := []byte{0x01, 0x02, 0x03, 0x04}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("method = %s, want POST", r.Method)
		}
		if r.Header.Get("Authorization") != "Api-Key secret-api-key" {
			t.Fatalf("Authorization = %q", r.Header.Get("Authorization"))
		}
		if r.Header.Get("Content-Type") != "application/octet-stream" {
			t.Fatalf("Content-Type = %q", r.Header.Get("Content-Type"))
		}
		query := r.URL.Query()
		if query.Get("lang") != "ru-RU" || query.Get("topic") != "general" {
			t.Fatalf("query = %v", query)
		}
		if query.Get("format") != "lpcm" || query.Get("sampleRateHertz") != "16000" {
			t.Fatalf("audio query = %v", query)
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read body: %v", err)
		}
		if string(body) != string(pcm) {
			t.Fatalf("body = %v, want %v", body, pcm)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"result":"  Добрый день  "}`))
	}))
	defer server.Close()

	client := newTestClient(t, server.URL)
	result, err := client.Transcribe(context.Background(), speechprovider.RecognitionRequest{
		PCM16LittleEndian: pcm,
		Language:          "ru-RU",
		SampleRateHertz:   16000,
		Channels:          1,
	})
	if err != nil {
		t.Fatalf("Transcribe() error = %v", err)
	}
	if result.Text != "Добрый день" {
		t.Fatalf("text = %q", result.Text)
	}
}

func TestClientMapsProviderStatusCodes(t *testing.T) {
	tests := []struct {
		name        string
		statusCode  int
		expectedErr error
	}{
		{name: "unauthorized", statusCode: http.StatusUnauthorized, expectedErr: speechprovider.ErrUnauthorized},
		{name: "rate limited", statusCode: http.StatusTooManyRequests, expectedErr: speechprovider.ErrUnavailable},
		{name: "server error", statusCode: http.StatusBadGateway, expectedErr: speechprovider.ErrUnavailable},
		{name: "rejected", statusCode: http.StatusBadRequest, expectedErr: speechprovider.ErrRejected},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(test.statusCode)
			}))
			defer server.Close()

			client := newTestClient(t, server.URL)
			_, err := client.Transcribe(context.Background(), speechprovider.RecognitionRequest{})
			if !errors.Is(err, test.expectedErr) {
				t.Fatalf("error = %v, want %v", err, test.expectedErr)
			}
		})
	}
}

func TestClientRejectsMalformedSuccessResponse(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`not-json`))
	}))
	defer server.Close()

	client := newTestClient(t, server.URL)
	_, err := client.Transcribe(context.Background(), speechprovider.RecognitionRequest{})
	if !errors.Is(err, speechprovider.ErrUnavailable) {
		t.Fatalf("error = %v, want ErrUnavailable", err)
	}
}

func newTestClient(t *testing.T, endpoint string) *Client {
	t.Helper()
	parsedEndpoint, err := url.Parse(endpoint)
	if err != nil {
		t.Fatalf("parse endpoint: %v", err)
	}
	return NewClient(parsedEndpoint, "secret-api-key", http.DefaultClient)
}
