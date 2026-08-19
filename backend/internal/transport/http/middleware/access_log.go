// Created by Rodion Kholodov.

package middleware

import (
	"log/slog"
	"net/http"
	"time"

	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/requestctx"
)

func AccessLog(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			startedAt := time.Now()
			wrappedWriter := chimiddleware.NewWrapResponseWriter(w, r.ProtoMajor)

			next.ServeHTTP(wrappedWriter, r)

			logger.InfoContext(
				r.Context(),
				"http request completed",
				"request_id", requestctx.RequestID(r.Context()),
				"method", r.Method,
				"path", r.URL.Path,
				"status", wrappedWriter.Status(),
				"response_bytes", wrappedWriter.BytesWritten(),
				"duration_ms", time.Since(startedAt).Milliseconds(),
			)
		})
	}
}
