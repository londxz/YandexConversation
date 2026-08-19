// Created by Rodion Kholodov.

package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/londxz/HackatonYandex/backend/internal/domain"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/requestctx"
	deviceusecase "github.com/londxz/HackatonYandex/backend/internal/usecase/devices"
)

type deviceServiceStub struct {
	registerSession domain.DeviceSession
	registerInput   deviceusecase.RegisterInput
	registerKey     string
	registerError   error
	registerCalls   int
	deleteDeviceID  string
	deleteError     error
}

func (stub *deviceServiceStub) Register(
	_ context.Context,
	input deviceusecase.RegisterInput,
	key string,
) (domain.DeviceSession, error) {
	stub.registerCalls++
	stub.registerInput = input
	stub.registerKey = key
	return stub.registerSession, stub.registerError
}

func (stub *deviceServiceStub) Refresh(
	context.Context,
	deviceusecase.RefreshInput,
	string,
) (domain.DeviceSession, error) {
	return domain.DeviceSession{}, nil
}

func (stub *deviceServiceStub) Delete(_ context.Context, deviceID string) error {
	stub.deleteDeviceID = deviceID
	return stub.deleteError
}

func TestDeviceHandlerRegisterReturnsContractSession(t *testing.T) {
	expiresAt := time.Date(2026, 8, 19, 18, 0, 0, 0, time.UTC)
	service := &deviceServiceStub{registerSession: domain.DeviceSession{
		DeviceID:     "72ab9284-7b7e-4f47-99b9-f7b682b2c718",
		AccessToken:  "access-token",
		RefreshToken: "refresh-token",
		ExpiresAt:    expiresAt,
	}}
	handler := NewDeviceHandler(service, handlerTestLogger())
	request := httptest.NewRequest(http.MethodPost, "/v1/devices/register", bytes.NewBufferString(`{
		"platform":"ios","app_version":"1.0.0","locale":"ru-RU"
	}`))
	request.Header.Set("Content-Type", "application/json; charset=utf-8")
	request.Header.Set("Idempotency-Key", "registration-key-0001")
	recorder := httptest.NewRecorder()

	handler.Register(recorder, request)

	if recorder.Code != http.StatusCreated {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusCreated)
	}
	if service.registerInput.Platform != "ios" || service.registerInput.Locale != "ru-RU" {
		t.Fatalf("register input = %#v", service.registerInput)
	}
	if service.registerKey != "registration-key-0001" {
		t.Fatalf("idempotency key = %q", service.registerKey)
	}

	var response map[string]any
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if response["device_id"] != service.registerSession.DeviceID {
		t.Fatalf("device_id = %v", response["device_id"])
	}
	if _, found := response["refresh_expires_at"]; found {
		t.Fatal("response exposes refresh_expires_at outside the contract")
	}
}

func TestDeviceHandlerRegisterRejectsUnknownFields(t *testing.T) {
	service := &deviceServiceStub{}
	handler := NewDeviceHandler(service, handlerTestLogger())
	request := httptest.NewRequest(http.MethodPost, "/v1/devices/register", bytes.NewBufferString(`{
		"platform":"ios","app_version":"1.0.0","locale":"ru-RU","debug":true
	}`))
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()

	handler.Register(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusBadRequest)
	}
	if service.registerCalls != 0 {
		t.Fatalf("register calls = %d, want 0", service.registerCalls)
	}
}

func TestDeviceHandlerRegisterRequiresJSONContentType(t *testing.T) {
	service := &deviceServiceStub{}
	handler := NewDeviceHandler(service, handlerTestLogger())
	request := httptest.NewRequest(http.MethodPost, "/v1/devices/register", bytes.NewBufferString(`{}`))
	request.Header.Set("Content-Type", "text/plain")
	recorder := httptest.NewRecorder()

	handler.Register(recorder, request)

	if recorder.Code != http.StatusUnsupportedMediaType {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusUnsupportedMediaType)
	}
}

func TestDeviceHandlerDeletePreventsDeletingAnotherDevice(t *testing.T) {
	service := &deviceServiceStub{}
	handler := NewDeviceHandler(service, handlerTestLogger())
	router := chi.NewRouter()
	router.Delete("/v1/devices/{device_id}", func(w http.ResponseWriter, r *http.Request) {
		ctx := requestctx.WithDeviceID(r.Context(), "72ab9284-7b7e-4f47-99b9-f7b682b2c718")
		handler.Delete(w, r.WithContext(ctx))
	})
	request := httptest.NewRequest(
		http.MethodDelete,
		"/v1/devices/86864fe5-17dc-4c4d-97b2-5f376e84f74b",
		nil,
	)
	recorder := httptest.NewRecorder()

	router.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusForbidden)
	}
	if service.deleteDeviceID != "" {
		t.Fatalf("deleted device ID = %q, want empty", service.deleteDeviceID)
	}
}

func handlerTestLogger() *slog.Logger {
	return slog.New(slog.NewJSONHandler(io.Discard, nil))
}
