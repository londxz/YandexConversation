// Created by Rodion Kholodov.

package postgres_test

import (
	"bytes"
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/londxz/HackatonYandex/backend/internal/config"
	"github.com/londxz/HackatonYandex/backend/internal/domain"
	"github.com/londxz/HackatonYandex/backend/internal/repository/postgres"
	"github.com/londxz/HackatonYandex/backend/internal/security"
	deviceusecase "github.com/londxz/HackatonYandex/backend/internal/usecase/devices"
)

func TestIntegrationDeviceRepositorySessionLifecycle(t *testing.T) {
	databaseURL := os.Getenv("TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	pool, err := postgres.Open(ctx, config.DatabaseConfig{
		URL:             databaseURL,
		ConnectTimeout:  5 * time.Second,
		HealthTimeout:   time.Second,
		MaxConnections:  4,
		MinConnections:  0,
		MaxConnLifetime: time.Minute,
		MaxConnIdleTime: time.Minute,
	})
	if err != nil {
		t.Fatalf("open test database: %v", err)
	}
	defer pool.Close()
	if _, err := pool.Exec(ctx, "TRUNCATE idempotency_keys, device_sessions, devices CASCADE"); err != nil {
		t.Fatalf("truncate test tables: %v", err)
	}
	t.Cleanup(func() {
		cleanupContext, cleanupCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cleanupCancel()
		_, _ = pool.Exec(cleanupContext, "TRUNCATE idempotency_keys, device_sessions, devices CASCADE")
	})

	credentials, err := security.NewCredentialManager(bytes.Repeat([]byte{0x51}, 32))
	if err != nil {
		t.Fatalf("create credentials: %v", err)
	}
	sealer, err := security.NewSealer(bytes.Repeat([]byte{0x61}, 32))
	if err != nil {
		t.Fatalf("create sealer: %v", err)
	}
	service := deviceusecase.NewService(
		postgres.NewDeviceRepository(pool),
		credentials,
		sealer,
		deviceusecase.SessionPolicy{
			AccessTokenTTL:  15 * time.Minute,
			RefreshTokenTTL: 90 * 24 * time.Hour,
			IdempotencyTTL:  24 * time.Hour,
		},
	)

	registration := deviceusecase.RegisterInput{
		Platform: "ios", AppVersion: "1.0.0", Locale: "ru-RU",
	}
	registered, err := service.Register(ctx, registration, "integration-register-0001")
	if err != nil {
		t.Fatalf("Register() error = %v", err)
	}
	replayed, err := service.Register(ctx, registration, "integration-register-0001")
	if err != nil {
		t.Fatalf("registration replay error = %v", err)
	}
	if registered != replayed {
		t.Fatalf("registration replay differs: first = %#v, replay = %#v", registered, replayed)
	}
	if _, err := service.Register(ctx, deviceusecase.RegisterInput{
		Platform: "ios", AppVersion: "1.0.1", Locale: "ru-RU",
	}, "integration-register-0001"); !errors.Is(err, domain.ErrIdempotencyConflict) {
		t.Fatalf("registration conflict error = %v, want ErrIdempotencyConflict", err)
	}

	var accessHashLength int
	var refreshHashLength int
	if err := pool.QueryRow(ctx, `
		SELECT octet_length(access_token_hash), octet_length(refresh_token_hash)
		FROM device_sessions WHERE device_id = $1
	`, registered.DeviceID).Scan(&accessHashLength, &refreshHashLength); err != nil {
		t.Fatalf("read stored token hashes: %v", err)
	}
	if accessHashLength != 32 || refreshHashLength != 32 {
		t.Fatalf("stored hash lengths = %d/%d, want 32/32", accessHashLength, refreshHashLength)
	}

	refreshed, err := service.Refresh(ctx, deviceusecase.RefreshInput{
		DeviceID: registered.DeviceID, RefreshToken: registered.RefreshToken,
	}, "integration-refresh-0001")
	if err != nil {
		t.Fatalf("Refresh() error = %v", err)
	}
	if _, err := service.Authenticate(ctx, registered.AccessToken); !errors.Is(err, domain.ErrInvalidCredentials) {
		t.Fatalf("old access token error = %v, want ErrInvalidCredentials", err)
	}
	if deviceID, err := service.Authenticate(ctx, refreshed.AccessToken); err != nil || deviceID != registered.DeviceID {
		t.Fatalf("new access token authentication = %q, %v", deviceID, err)
	}
	refreshReplay, err := service.Refresh(ctx, deviceusecase.RefreshInput{
		DeviceID: registered.DeviceID, RefreshToken: registered.RefreshToken,
	}, "integration-refresh-0001")
	if err != nil {
		t.Fatalf("refresh replay error = %v", err)
	}
	if refreshed != refreshReplay {
		t.Fatalf("refresh replay differs: first = %#v, replay = %#v", refreshed, refreshReplay)
	}

	if err := service.Delete(ctx, registered.DeviceID); err != nil {
		t.Fatalf("Delete() error = %v", err)
	}
	var deviceCount int
	var sessionCount int
	var idempotencyCount int
	if err := pool.QueryRow(ctx, "SELECT count(*) FROM devices").Scan(&deviceCount); err != nil {
		t.Fatalf("count devices: %v", err)
	}
	if err := pool.QueryRow(ctx, "SELECT count(*) FROM device_sessions").Scan(&sessionCount); err != nil {
		t.Fatalf("count sessions: %v", err)
	}
	if err := pool.QueryRow(ctx, "SELECT count(*) FROM idempotency_keys").Scan(&idempotencyCount); err != nil {
		t.Fatalf("count idempotency records: %v", err)
	}
	if deviceCount != 0 || sessionCount != 0 || idempotencyCount != 0 {
		t.Fatalf(
			"rows after deletion: devices=%d sessions=%d idempotency=%d",
			deviceCount, sessionCount, idempotencyCount,
		)
	}
}
