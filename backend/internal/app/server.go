// Created by Rodion Kholodov.

package app

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/londxz/HackatonYandex/backend/internal/config"
)

type Server struct {
	httpServer *http.Server
	logger     *slog.Logger
}

func NewServer(httpConfig config.HTTPConfig, handler http.Handler, logger *slog.Logger) *Server {
	return &Server{
		httpServer: &http.Server{
			Addr:              httpConfig.Address,
			Handler:           handler,
			ReadHeaderTimeout: httpConfig.ReadHeaderTimeout,
			ReadTimeout:       httpConfig.ReadTimeout,
			WriteTimeout:      httpConfig.WriteTimeout,
			IdleTimeout:       httpConfig.IdleTimeout,
			MaxHeaderBytes:    1 << 20,
		},
		logger: logger,
	}
}

func (server *Server) Run() error {
	err := server.httpServer.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("serve HTTP: %w", err)
	}
	return nil
}

func (server *Server) Shutdown(ctx context.Context) error {
	server.logger.InfoContext(ctx, "HTTP server shutdown started")
	if err := server.httpServer.Shutdown(ctx); err != nil {
		return fmt.Errorf("shutdown HTTP server: %w", err)
	}
	server.logger.InfoContext(ctx, "HTTP server shutdown completed")
	return nil
}
