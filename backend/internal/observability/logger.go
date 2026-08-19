// Created by Rodion Kholodov.

package observability

import (
	"io"
	"log/slog"
)

func NewLogger(output io.Writer, environment string, level string) *slog.Logger {
	options := &slog.HandlerOptions{Level: parseLevel(level)}
	handler := slog.NewJSONHandler(output, options)

	return slog.New(handler).With(
		"service", "razgovor-api",
		"environment", environment,
	)
}

func parseLevel(level string) slog.Level {
	switch level {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
