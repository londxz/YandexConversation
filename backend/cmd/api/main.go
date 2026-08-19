// Created by Rodion Kholodov.

package main

import (
	"context"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/londxz/HackatonYandex/backend/internal/app"
	"github.com/londxz/HackatonYandex/backend/internal/buildinfo"
	"github.com/londxz/HackatonYandex/backend/internal/config"
	"github.com/londxz/HackatonYandex/backend/internal/observability"
	"github.com/londxz/HackatonYandex/backend/internal/repository/postgres"
	"github.com/londxz/HackatonYandex/backend/internal/security"
	speechprovider "github.com/londxz/HackatonYandex/backend/internal/speech"
	yandexspeech "github.com/londxz/HackatonYandex/backend/internal/speech/yandex"
	httptransport "github.com/londxz/HackatonYandex/backend/internal/transport/http"
	"github.com/londxz/HackatonYandex/backend/internal/transport/http/handlers"
	deviceusecase "github.com/londxz/HackatonYandex/backend/internal/usecase/devices"
	speechusecase "github.com/londxz/HackatonYandex/backend/internal/usecase/speech"
)

func main() {
	os.Exit(run())
}

func run() int {
	bootstrapLogger := observability.NewLogger(os.Stdout, "unknown", "info")
	appConfig, err := config.Load()
	if err != nil {
		bootstrapLogger.Error("configuration is invalid", "error", err)
		return 1
	}

	logger := observability.NewLogger(os.Stdout, appConfig.Environment, appConfig.LogLevel)
	startupContext, cancelStartup := context.WithTimeout(context.Background(), appConfig.Database.ConnectTimeout)
	defer cancelStartup()

	pool, err := postgres.Open(startupContext, appConfig.Database)
	if err != nil {
		logger.Error("database initialization failed", "error", err)
		return 1
	}
	defer pool.Close()
	credentials, err := security.NewCredentialManager(appConfig.Secrets.TokenPepper)
	if err != nil {
		logger.Error("credential manager initialization failed", "error", err)
		return 1
	}
	idempotencySealer, err := security.NewSealer(appConfig.Secrets.IdempotencyEncryptionKey)
	if err != nil {
		logger.Error("idempotency encryption initialization failed", "error", err)
		return 1
	}
	deviceRepository := postgres.NewDeviceRepository(pool)
	deviceService := deviceusecase.NewService(
		deviceRepository,
		credentials,
		idempotencySealer,
		deviceusecase.SessionPolicy{
			AccessTokenTTL:  appConfig.DeviceSessions.AccessTokenTTL,
			RefreshTokenTTL: appConfig.DeviceSessions.RefreshTokenTTL,
			IdempotencyTTL:  appConfig.DeviceSessions.IdempotencyTTL,
		},
	)
	var speechProvider speechprovider.Provider = speechprovider.UnavailableProvider{}
	if appConfig.Speech.Provider == "yandex" {
		endpoint, err := url.Parse(appConfig.Speech.YandexEndpoint)
		if err != nil {
			logger.Error("speech provider endpoint is invalid", "error", err)
			return 1
		}
		speechProvider = yandexspeech.NewClient(
			endpoint,
			appConfig.Speech.YandexAPIKey,
			&http.Client{
				Timeout: appConfig.Speech.RecognitionTimeout + 5*time.Second,
				CheckRedirect: func(*http.Request, []*http.Request) error {
					return http.ErrUseLastResponse
				},
			},
		)
	}
	speechService := speechusecase.NewService(
		speechProvider,
		speechusecase.Policy{
			RecognitionTimeout: appConfig.Speech.RecognitionTimeout,
			MaxAudioBytes:      appConfig.Speech.MaxAudioBytes,
			MaxDuration:        appConfig.Speech.MaxDuration,
			SupportedLanguages: appConfig.Speech.SupportedLanguages,
			MaxConcurrent:      appConfig.Speech.MaxConcurrent,
		},
	)

	healthHandler := handlers.NewHealthHandler(
		pool,
		logger,
		buildinfo.Version,
		appConfig.Database.HealthTimeout,
	)
	deviceHandler := handlers.NewDeviceHandler(deviceService, logger)
	speechHandler := handlers.NewSpeechHandler(
		speechService,
		logger,
		appConfig.Speech.MaxAudioBytes,
	)
	router := httptransport.NewRouter(httptransport.RouterDependencies{
		Logger:              logger,
		HealthHandler:       healthHandler,
		DeviceHandler:       deviceHandler,
		SpeechHandler:       speechHandler,
		DeviceAuthenticator: deviceService,
		MaxBodyBytes:        appConfig.HTTP.MaxBodyBytes,
	})
	server := app.NewServer(appConfig.HTTP, router, logger)

	signalContext, stopSignals := signal.NotifyContext(
		context.Background(),
		syscall.SIGINT,
		syscall.SIGTERM,
	)
	defer stopSignals()

	serverErrors := make(chan error, 1)
	go func() {
		serverErrors <- server.Run()
	}()

	logger.Info(
		"HTTP server started",
		"address", appConfig.HTTP.Address,
		"version", buildinfo.Version,
		"commit", buildinfo.Commit,
		"build_time", buildinfo.BuildTime,
	)

	select {
	case err := <-serverErrors:
		if err != nil {
			logger.Error("HTTP server stopped unexpectedly", "error", err)
			return 1
		}
		return 0
	case <-signalContext.Done():
		logger.Info("shutdown signal received")
	}

	shutdownContext, cancelShutdown := context.WithTimeout(context.Background(), appConfig.ShutdownTimeout)
	defer cancelShutdown()
	if err := server.Shutdown(shutdownContext); err != nil {
		logger.Error("graceful shutdown failed", "error", err)
		return 1
	}

	waitForServerExit(logger, serverErrors)
	return 0
}

func waitForServerExit(logger *slog.Logger, serverErrors <-chan error) {
	select {
	case err := <-serverErrors:
		if err != nil {
			logger.Error("HTTP server returned an error during shutdown", "error", err)
		}
	case <-time.After(time.Second):
		logger.Warn("timed out waiting for HTTP server goroutine")
	}
}
