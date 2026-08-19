// Created by Rodion Kholodov.

package middleware

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/londxz/HackatonYandex/backend/internal/domain"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/requestctx"
)

type authenticatorStub struct {
	deviceID string
	err      error
	token    string
}

func (stub *authenticatorStub) Authenticate(_ context.Context, token string) (string, error) {
	stub.token = token
	return stub.deviceID, stub.err
}

func TestRequireAccessTokenAddsDeviceIDToContext(t *testing.T) {
	authenticator := &authenticatorStub{deviceID: "72ab9284-7b7e-4f47-99b9-f7b682b2c718"}
	handler := RequireAccessToken(authenticator, testLogger())(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(requestctx.DeviceID(r.Context())))
	}))
	request := httptest.NewRequest(http.MethodDelete, "/v1/devices/id", nil)
	request.Header.Set("Authorization", "Bearer rv_access_token")
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusOK)
	}
	if recorder.Body.String() != authenticator.deviceID {
		t.Fatalf("body = %q, want device ID", recorder.Body.String())
	}
	if authenticator.token != "rv_access_token" {
		t.Fatalf("authenticated token = %q", authenticator.token)
	}
}

func TestRequireAccessTokenRejectsMissingAndInvalidCredentials(t *testing.T) {
	tests := []struct {
		name          string
		authorization string
		authenticator *authenticatorStub
	}{
		{name: "missing header", authenticator: &authenticatorStub{}},
		{
			name:          "invalid token",
			authorization: "Bearer invalid",
			authenticator: &authenticatorStub{err: domain.ErrInvalidCredentials},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			handler := RequireAccessToken(test.authenticator, testLogger())(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
				t.Fatal("protected handler was called")
			}))
			request := httptest.NewRequest(http.MethodDelete, "/v1/devices/id", nil)
			request.Header.Set("Authorization", test.authorization)
			recorder := httptest.NewRecorder()

			handler.ServeHTTP(recorder, request)

			if recorder.Code != http.StatusUnauthorized {
				t.Fatalf("status = %d, want %d", recorder.Code, http.StatusUnauthorized)
			}
			if recorder.Header().Get("WWW-Authenticate") != "Bearer" {
				t.Fatalf("WWW-Authenticate = %q", recorder.Header().Get("WWW-Authenticate"))
			}
		})
	}
}

func TestRequireAccessTokenReturnsUnavailableForRepositoryFailure(t *testing.T) {
	authenticator := &authenticatorStub{err: errors.New("database unavailable")}
	handler := RequireAccessToken(authenticator, testLogger())(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		t.Fatal("protected handler was called")
	}))
	request := httptest.NewRequest(http.MethodDelete, "/v1/devices/id", nil)
	request.Header.Set("Authorization", "Bearer token")
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusServiceUnavailable)
	}
}

func testLogger() *slog.Logger {
	return slog.New(slog.NewJSONHandler(io.Discard, nil))
}
