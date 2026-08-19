// Created by Rodion Kholodov.

package middleware

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/londxz/HackatonYandex/backend/internal/transport/http/requestctx"
)

func TestRequestIDGeneratesAndPropagatesIdentifier(t *testing.T) {
	var contextRequestID string
	handler := RequestID(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		contextRequestID = requestctx.RequestID(r.Context())
		w.WriteHeader(http.StatusNoContent)
	}))
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/", nil))

	headerRequestID := recorder.Header().Get("X-Request-ID")
	if !strings.HasPrefix(headerRequestID, "req_") {
		t.Fatalf("generated request ID = %q, want req_ prefix", headerRequestID)
	}
	if contextRequestID != headerRequestID {
		t.Fatalf("context request ID = %q, header = %q", contextRequestID, headerRequestID)
	}
}

func TestRequestIDReplacesUnsafeClientValue(t *testing.T) {
	handler := RequestID(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	request.Header.Set("X-Request-ID", "contains spaces and user text")
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, request)

	if got := recorder.Header().Get("X-Request-ID"); !strings.HasPrefix(got, "req_") {
		t.Fatalf("request ID = %q, want generated value", got)
	}
}
