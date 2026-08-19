// Created by Rodion Kholodov.

package httptransport

import (
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/handlers"
	appmiddleware "github.com/londxz/HackatonYandex/backend/internal/transport/http/middleware"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/respond"
)

type RouterDependencies struct {
	Logger              *slog.Logger
	HealthHandler       *handlers.HealthHandler
	DeviceHandler       *handlers.DeviceHandler
	SpeechHandler       *handlers.SpeechHandler
	SpeechStreamHandler http.Handler
	DeviceAuthenticator appmiddleware.AccessTokenAuthenticator
	MaxBodyBytes        int64
}

func NewRouter(dependencies RouterDependencies) http.Handler {
	router := chi.NewRouter()
	router.Use(appmiddleware.RequestID)
	router.Use(appmiddleware.AccessLog(dependencies.Logger))
	router.Use(appmiddleware.Recovery(dependencies.Logger))
	router.Use(appmiddleware.SecurityHeaders)
	router.Use(appmiddleware.MaxBodyBytes(dependencies.MaxBodyBytes))

	router.Get("/livez", dependencies.HealthHandler.Live)
	router.Get("/readyz", dependencies.HealthHandler.Ready)
	router.Get("/v1/health", dependencies.HealthHandler.Public)
	router.Route("/v1/devices", func(router chi.Router) {
		router.Post("/register", dependencies.DeviceHandler.Register)
		router.Post("/refresh", dependencies.DeviceHandler.Refresh)
		router.With(
			appmiddleware.RequireAccessToken(dependencies.DeviceAuthenticator, dependencies.Logger),
		).Delete("/{device_id}", dependencies.DeviceHandler.Delete)
	})
	router.With(
		appmiddleware.RequireAccessToken(dependencies.DeviceAuthenticator, dependencies.Logger),
	).Post("/v1/speech/transcribe", dependencies.SpeechHandler.Transcribe)
	router.With(
		appmiddleware.RequireAccessToken(dependencies.DeviceAuthenticator, dependencies.Logger),
	).Handle("/v1/speech/stream", dependencies.SpeechStreamHandler)

	router.NotFound(func(w http.ResponseWriter, r *http.Request) {
		respond.Error(w, r, http.StatusNotFound, "not_found", "Resource not found.")
	})
	router.MethodNotAllowed(func(w http.ResponseWriter, r *http.Request) {
		respond.Error(w, r, http.StatusMethodNotAllowed, "method_not_allowed", "Method not allowed.")
	})

	return router
}
