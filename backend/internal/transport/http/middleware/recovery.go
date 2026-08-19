// Created by Rodion Kholodov.

package middleware

import (
	"log/slog"
	"net/http"
	"runtime/debug"

	"github.com/londxz/HackatonYandex/backend/internal/transport/http/requestctx"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/respond"
)

func Recovery(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			defer func() {
				if recovered := recover(); recovered != nil {
					logger.ErrorContext(
						r.Context(),
						"panic recovered",
						"request_id", requestctx.RequestID(r.Context()),
						"panic", recovered,
						"stack", string(debug.Stack()),
					)
					respond.Error(
						w,
						r,
						http.StatusInternalServerError,
						"internal_error",
						"An internal error occurred.",
					)
				}
			}()

			next.ServeHTTP(w, r)
		})
	}
}
