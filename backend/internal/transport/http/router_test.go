// Created by Rodion Kholodov.

package httptransport_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/londxz/HackatonYandex/backend/internal/domain"
	httptransport "github.com/londxz/HackatonYandex/backend/internal/transport/http"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/handlers"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/respond"
	deviceusecase "github.com/londxz/HackatonYandex/backend/internal/usecase/devices"
)

type pingerStub struct {
	err       error
	callCount int
}

type routerDeviceServiceStub struct{}

func (*routerDeviceServiceStub) Register(
	context.Context,
	deviceusecase.RegisterInput,
	string,
) (domain.DeviceSession, error) {
	return domain.DeviceSession{}, nil
}

func (*routerDeviceServiceStub) Refresh(
	context.Context,
	deviceusecase.RefreshInput,
	string,
) (domain.DeviceSession, error) {
	return domain.DeviceSession{}, nil
}

func (*routerDeviceServiceStub) Authenticate(context.Context, string) (string, error) {
	return "72ab9284-7b7e-4f47-99b9-f7b682b2c718", nil
}

func (*routerDeviceServiceStub) Delete(context.Context, string) error {
	return nil
}

func (stub *pingerStub) Ping(context.Context) error {
	stub.callCount++
	return stub.err
}

func TestHealthReturnsContractResponseAndRequestID(t *testing.T) {
	pinger := &pingerStub{}
	router := newTestRouter(pinger)
	request := httptest.NewRequest(http.MethodGet, "/v1/health", nil)
	request.Header.Set("X-Request-ID", "request-from-client")
	recorder := httptest.NewRecorder()

	router.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusOK)
	}
	if got := recorder.Header().Get("X-Request-ID"); got != "request-from-client" {
		t.Fatalf("X-Request-ID = %q, want request-from-client", got)
	}
	if got := recorder.Header().Get("Cache-Control"); got != "no-store" {
		t.Fatalf("Cache-Control = %q, want no-store", got)
	}

	var response struct {
		Status  string    `json:"status"`
		Version string    `json:"version"`
		Time    time.Time `json:"time"`
	}
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if response.Status != "ok" {
		t.Fatalf("status body = %q, want ok", response.Status)
	}
	if response.Version != "test-version" {
		t.Fatalf("version = %q, want test-version", response.Version)
	}
	if response.Time.IsZero() {
		t.Fatal("time is zero")
	}
	if pinger.callCount != 1 {
		t.Fatalf("Ping call count = %d, want 1", pinger.callCount)
	}
}

func TestReadyReturnsStandardErrorWhenDatabaseIsUnavailable(t *testing.T) {
	pinger := &pingerStub{err: errors.New("database unavailable")}
	router := newTestRouter(pinger)
	request := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	recorder := httptest.NewRecorder()

	router.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusServiceUnavailable)
	}

	var response respond.ErrorEnvelope
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if response.Error.Code != "service_unavailable" {
		t.Fatalf("error code = %q, want service_unavailable", response.Error.Code)
	}
	if response.Error.RequestID == "" {
		t.Fatal("request ID is empty")
	}
}

func TestLiveDoesNotDependOnDatabase(t *testing.T) {
	pinger := &pingerStub{err: errors.New("database unavailable")}
	router := newTestRouter(pinger)
	request := httptest.NewRequest(http.MethodGet, "/livez", nil)
	recorder := httptest.NewRecorder()

	router.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusOK)
	}
	if pinger.callCount != 0 {
		t.Fatalf("Ping call count = %d, want 0", pinger.callCount)
	}
}

func TestUnknownRouteUsesStandardErrorEnvelope(t *testing.T) {
	router := newTestRouter(&pingerStub{})
	request := httptest.NewRequest(http.MethodGet, "/missing", nil)
	recorder := httptest.NewRecorder()

	router.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusNotFound)
	}
	var response respond.ErrorEnvelope
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if response.Error.Code != "not_found" {
		t.Fatalf("error code = %q, want not_found", response.Error.Code)
	}
}

func newTestRouter(pinger handlers.Pinger) http.Handler {
	logger := slog.New(slog.NewJSONHandler(io.Discard, nil))
	healthHandler := handlers.NewHealthHandler(pinger, logger, "test-version", 100*time.Millisecond)
	deviceService := &routerDeviceServiceStub{}
	return httptransport.NewRouter(httptransport.RouterDependencies{
		Logger:              logger,
		HealthHandler:       healthHandler,
		DeviceHandler:       handlers.NewDeviceHandler(deviceService, logger),
		DeviceAuthenticator: deviceService,
		MaxBodyBytes:        1024,
	})
}
