// Created by Rodion Kholodov.

package handlers

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/londxz/HackatonYandex/backend/internal/transport/http/requestctx"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/respond"
)

type Pinger interface {
	Ping(context.Context) error
}

type HealthHandler struct {
	pinger        Pinger
	logger        *slog.Logger
	version       string
	healthTimeout time.Duration
	now           func() time.Time
}

type healthResponse struct {
	Status  string    `json:"status"`
	Version string    `json:"version"`
	Time    time.Time `json:"time"`
}

type probeResponse struct {
	Status string `json:"status"`
}

func NewHealthHandler(
	pinger Pinger,
	logger *slog.Logger,
	version string,
	healthTimeout time.Duration,
) *HealthHandler {
	return &HealthHandler{
		pinger:        pinger,
		logger:        logger,
		version:       version,
		healthTimeout: healthTimeout,
		now:           time.Now,
	}
}

func (handler *HealthHandler) Public(w http.ResponseWriter, r *http.Request) {
	if err := handler.ping(r.Context()); err != nil {
		handler.logDependencyFailure(r, err)
		respond.Error(
			w,
			r,
			http.StatusServiceUnavailable,
			"service_unavailable",
			"Service is temporarily unavailable.",
		)
		return
	}

	respond.JSON(w, http.StatusOK, healthResponse{
		Status:  "ok",
		Version: handler.version,
		Time:    handler.now().UTC(),
	})
}

func (handler *HealthHandler) Live(w http.ResponseWriter, _ *http.Request) {
	respond.JSON(w, http.StatusOK, probeResponse{Status: "ok"})
}

func (handler *HealthHandler) Ready(w http.ResponseWriter, r *http.Request) {
	if err := handler.ping(r.Context()); err != nil {
		handler.logDependencyFailure(r, err)
		respond.Error(
			w,
			r,
			http.StatusServiceUnavailable,
			"service_unavailable",
			"Service is not ready.",
		)
		return
	}

	respond.JSON(w, http.StatusOK, probeResponse{Status: "ok"})
}

func (handler *HealthHandler) ping(parent context.Context) error {
	ctx, cancel := context.WithTimeout(parent, handler.healthTimeout)
	defer cancel()
	return handler.pinger.Ping(ctx)
}

func (handler *HealthHandler) logDependencyFailure(r *http.Request, err error) {
	handler.logger.WarnContext(
		r.Context(),
		"health dependency check failed",
		"request_id", requestctx.RequestID(r.Context()),
		"dependency", "postgres",
		"error", err,
	)
}
