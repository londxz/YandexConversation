// Created by Rodion Kholodov.

package middleware

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/londxz/HackatonYandex/backend/internal/domain"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/requestctx"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/respond"
)

type AccessTokenAuthenticator interface {
	Authenticate(context.Context, string) (string, error)
}

func RequireAccessToken(
	authenticator AccessTokenAuthenticator,
	logger *slog.Logger,
) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			token, ok := bearerToken(r.Header.Get("Authorization"))
			if !ok {
				unauthorized(w, r)
				return
			}

			deviceID, err := authenticator.Authenticate(r.Context(), token)
			if errors.Is(err, domain.ErrInvalidCredentials) {
				unauthorized(w, r)
				return
			}
			if err != nil {
				logger.ErrorContext(
					r.Context(),
					"access token authentication failed",
					"request_id", requestctx.RequestID(r.Context()),
					"error", err,
				)
				respond.Error(w, r, http.StatusServiceUnavailable, "service_unavailable", "Service is temporarily unavailable.")
				return
			}

			ctx := requestctx.WithDeviceID(r.Context(), deviceID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func bearerToken(header string) (string, bool) {
	parts := strings.Fields(header)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || len(parts[1]) > 256 {
		return "", false
	}
	return parts[1], true
}

func unauthorized(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("WWW-Authenticate", "Bearer")
	respond.Error(w, r, http.StatusUnauthorized, "invalid_credentials", "Authentication credentials are invalid or expired.")
}
