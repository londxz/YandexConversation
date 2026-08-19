// Created by Rodion Kholodov.

package handlers

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/londxz/HackatonYandex/backend/internal/domain"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/requestctx"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/respond"
	deviceusecase "github.com/londxz/HackatonYandex/backend/internal/usecase/devices"
)

const deviceRequestMaxBytes = 16 << 10

type DeviceService interface {
	Register(context.Context, deviceusecase.RegisterInput, string) (domain.DeviceSession, error)
	Refresh(context.Context, deviceusecase.RefreshInput, string) (domain.DeviceSession, error)
	Delete(context.Context, string) error
}

type DeviceHandler struct {
	service DeviceService
	logger  *slog.Logger
}

func NewDeviceHandler(service DeviceService, logger *slog.Logger) *DeviceHandler {
	return &DeviceHandler{service: service, logger: logger}
}

type registerDeviceRequest struct {
	Platform   string `json:"platform"`
	AppVersion string `json:"app_version"`
	Locale     string `json:"locale"`
}

type refreshDeviceRequest struct {
	DeviceID     string `json:"device_id"`
	RefreshToken string `json:"refresh_token"`
}

type deviceSessionResponse struct {
	DeviceID     string    `json:"device_id"`
	AccessToken  string    `json:"access_token"`
	RefreshToken string    `json:"refresh_token"`
	ExpiresAt    time.Time `json:"expires_at"`
}

func (handler *DeviceHandler) Register(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, deviceRequestMaxBytes)
	var request registerDeviceRequest
	if err := decodeJSON(r, &request); err != nil {
		handler.writeDecodeError(w, r, err)
		return
	}

	session, err := handler.service.Register(r.Context(), deviceusecase.RegisterInput{
		Platform:   request.Platform,
		AppVersion: request.AppVersion,
		Locale:     request.Locale,
	}, r.Header.Get("Idempotency-Key"))
	if err != nil {
		handler.writeServiceError(w, r, err)
		return
	}
	respond.JSON(w, http.StatusCreated, responseFromSession(session))
}

func (handler *DeviceHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, deviceRequestMaxBytes)
	var request refreshDeviceRequest
	if err := decodeJSON(r, &request); err != nil {
		handler.writeDecodeError(w, r, err)
		return
	}

	session, err := handler.service.Refresh(r.Context(), deviceusecase.RefreshInput{
		DeviceID:     request.DeviceID,
		RefreshToken: request.RefreshToken,
	}, r.Header.Get("Idempotency-Key"))
	if err != nil {
		handler.writeServiceError(w, r, err)
		return
	}
	respond.JSON(w, http.StatusOK, responseFromSession(session))
}

func (handler *DeviceHandler) Delete(w http.ResponseWriter, r *http.Request) {
	pathDeviceID := chi.URLParam(r, "device_id")
	if pathDeviceID != requestctx.DeviceID(r.Context()) {
		respond.Error(w, r, http.StatusForbidden, "forbidden", "The authenticated device cannot delete this resource.")
		return
	}

	if err := handler.service.Delete(r.Context(), pathDeviceID); err != nil {
		handler.writeServiceError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (handler *DeviceHandler) writeDecodeError(w http.ResponseWriter, r *http.Request, err error) {
	var maxBytesError *http.MaxBytesError
	if errors.As(err, &maxBytesError) {
		respond.Error(w, r, http.StatusRequestEntityTooLarge, "payload_too_large", "Request body is too large.")
		return
	}
	if errors.Is(err, errUnsupportedMediaType) {
		respond.Error(w, r, http.StatusUnsupportedMediaType, "unsupported_media_type", "Content-Type must be application/json.")
		return
	}
	respond.Error(w, r, http.StatusBadRequest, "invalid_request", "Request body is invalid.")
}

func (handler *DeviceHandler) writeServiceError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, domain.ErrInvalidInput):
		respond.Error(w, r, http.StatusBadRequest, "invalid_request", "Request parameters are invalid.")
	case errors.Is(err, domain.ErrIdempotencyConflict):
		respond.Error(w, r, http.StatusConflict, "idempotency_conflict", "Idempotency-Key was already used for another request.")
	case errors.Is(err, domain.ErrInvalidCredentials):
		respond.Error(w, r, http.StatusUnauthorized, "invalid_credentials", "Authentication credentials are invalid or expired.")
	case errors.Is(err, domain.ErrDeviceNotFound):
		respond.Error(w, r, http.StatusNotFound, "not_found", "Device was not found.")
	default:
		handler.logger.ErrorContext(
			r.Context(),
			"device request failed",
			"request_id", requestctx.RequestID(r.Context()),
			"error", err,
		)
		respond.Error(w, r, http.StatusInternalServerError, "internal_error", "An internal error occurred.")
	}
}

func responseFromSession(session domain.DeviceSession) deviceSessionResponse {
	return deviceSessionResponse{
		DeviceID:     session.DeviceID,
		AccessToken:  session.AccessToken,
		RefreshToken: session.RefreshToken,
		ExpiresAt:    session.ExpiresAt,
	}
}
