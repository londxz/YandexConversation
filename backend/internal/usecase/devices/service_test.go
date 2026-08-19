// Created by Rodion Kholodov.

package devices

import (
	"bytes"
	"context"
	"errors"
	"testing"
	"time"

	"github.com/londxz/HackatonYandex/backend/internal/domain"
	"github.com/londxz/HackatonYandex/backend/internal/security"
)

func TestRegisterIsIdempotentAndRejectsChangedRequest(t *testing.T) {
	repository := newMemoryRepository()
	service := newTestService(t, repository)
	input := RegisterInput{Platform: "ios", AppVersion: "1.0.0", Locale: "ru-RU"}
	key := "registration-key-0001"

	first, err := service.Register(context.Background(), input, key)
	if err != nil {
		t.Fatalf("first Register() error = %v", err)
	}
	second, err := service.Register(context.Background(), input, key)
	if err != nil {
		t.Fatalf("second Register() error = %v", err)
	}

	if first != second {
		t.Fatalf("idempotent sessions differ: first = %#v, second = %#v", first, second)
	}
	if repository.createdDevices != 1 {
		t.Fatalf("created devices = %d, want 1", repository.createdDevices)
	}

	changed := input
	changed.Locale = "en-US"
	if _, err := service.Register(context.Background(), changed, key); !errors.Is(err, domain.ErrIdempotencyConflict) {
		t.Fatalf("changed Register() error = %v, want ErrIdempotencyConflict", err)
	}
}

func TestSessionLifecycleRotatesTokensAndDeletesDevice(t *testing.T) {
	repository := newMemoryRepository()
	service := newTestService(t, repository)
	ctx := context.Background()
	registered, err := service.Register(ctx, RegisterInput{
		Platform: "ios", AppVersion: "2.4.1", Locale: "ru-RU",
	}, "registration-key-0002")
	if err != nil {
		t.Fatalf("Register() error = %v", err)
	}

	deviceID, err := service.Authenticate(ctx, registered.AccessToken)
	if err != nil {
		t.Fatalf("Authenticate() error = %v", err)
	}
	if deviceID != registered.DeviceID {
		t.Fatalf("authenticated device ID = %q, want %q", deviceID, registered.DeviceID)
	}

	refreshed, err := service.Refresh(ctx, RefreshInput{
		DeviceID: registered.DeviceID, RefreshToken: registered.RefreshToken,
	}, "refresh-session-key-0001")
	if err != nil {
		t.Fatalf("Refresh() error = %v", err)
	}
	if refreshed.AccessToken == registered.AccessToken || refreshed.RefreshToken == registered.RefreshToken {
		t.Fatal("Refresh() did not rotate both tokens")
	}
	if _, err := service.Authenticate(ctx, registered.AccessToken); !errors.Is(err, domain.ErrInvalidCredentials) {
		t.Fatalf("old access token error = %v, want ErrInvalidCredentials", err)
	}
	if _, err := service.Authenticate(ctx, refreshed.AccessToken); err != nil {
		t.Fatalf("new access token Authenticate() error = %v", err)
	}

	replayed, err := service.Refresh(ctx, RefreshInput{
		DeviceID: registered.DeviceID, RefreshToken: registered.RefreshToken,
	}, "refresh-session-key-0001")
	if err != nil {
		t.Fatalf("idempotent Refresh() error = %v", err)
	}
	if refreshed != replayed {
		t.Fatalf("refresh replay differs: first = %#v, replay = %#v", refreshed, replayed)
	}
	if _, err := service.Refresh(ctx, RefreshInput{
		DeviceID: registered.DeviceID, RefreshToken: registered.RefreshToken,
	}, "refresh-session-key-0002"); !errors.Is(err, domain.ErrInvalidCredentials) {
		t.Fatalf("reused refresh token error = %v, want ErrInvalidCredentials", err)
	}

	if err := service.Delete(ctx, registered.DeviceID); err != nil {
		t.Fatalf("Delete() error = %v", err)
	}
	if _, err := service.Authenticate(ctx, refreshed.AccessToken); !errors.Is(err, domain.ErrInvalidCredentials) {
		t.Fatalf("deleted device token error = %v, want ErrInvalidCredentials", err)
	}
}

func TestRegisterRejectsInvalidInputBeforeRepository(t *testing.T) {
	repository := newMemoryRepository()
	service := newTestService(t, repository)

	_, err := service.Register(context.Background(), RegisterInput{
		Platform: "android", AppVersion: "1.0", Locale: "ru-RU",
	}, "registration-key-0003")
	if !errors.Is(err, domain.ErrInvalidInput) {
		t.Fatalf("Register() error = %v, want ErrInvalidInput", err)
	}
	if repository.createdDevices != 0 {
		t.Fatalf("created devices = %d, want 0", repository.createdDevices)
	}
}

func newTestService(t *testing.T, repository Repository) *Service {
	t.Helper()
	credentials, err := security.NewCredentialManager(bytes.Repeat([]byte{0x11}, 32))
	if err != nil {
		t.Fatalf("NewCredentialManager() error = %v", err)
	}
	sealer, err := security.NewSealer(bytes.Repeat([]byte{0x22}, 32))
	if err != nil {
		t.Fatalf("NewSealer() error = %v", err)
	}
	service := NewService(repository, credentials, sealer, SessionPolicy{
		AccessTokenTTL:  15 * time.Minute,
		RefreshTokenTTL: 90 * 24 * time.Hour,
		IdempotencyTTL:  24 * time.Hour,
	})
	service.now = func() time.Time {
		return time.Date(2026, 8, 19, 17, 0, 0, 0, time.UTC)
	}
	return service
}

type memoryIdempotency struct {
	requestHash []byte
	response    []byte
}

type memoryRepository struct {
	idempotency    map[string]memoryIdempotency
	accessTokens   map[string]string
	refreshTokens  map[string]string
	devices        map[string]bool
	createdDevices int
}

func newMemoryRepository() *memoryRepository {
	return &memoryRepository{
		idempotency:   make(map[string]memoryIdempotency),
		accessTokens:  make(map[string]string),
		refreshTokens: make(map[string]string),
		devices:       make(map[string]bool),
	}
}

func (repository *memoryRepository) CreateDevice(
	_ context.Context,
	params CreateDeviceParams,
) (IdempotencyResult, error) {
	if result, found, err := repository.replay(params.IdempotencyRecord); found || err != nil {
		return result, err
	}

	repository.storeIdempotency(params.IdempotencyRecord)
	repository.devices[params.DeviceID] = true
	repository.accessTokens[string(params.AccessTokenHash)] = params.DeviceID
	repository.refreshTokens[string(params.RefreshTokenHash)] = params.DeviceID
	repository.createdDevices++
	return IdempotencyResult{EncryptedResponse: params.IdempotencyRecord.EncryptedResponse}, nil
}

func (repository *memoryRepository) RotateSession(
	_ context.Context,
	params RotateSessionParams,
) (IdempotencyResult, error) {
	if result, found, err := repository.replay(params.IdempotencyRecord); found || err != nil {
		return result, err
	}
	deviceID, found := repository.refreshTokens[string(params.PreviousTokenHash)]
	if !found || deviceID != params.DeviceID || !repository.devices[params.DeviceID] {
		return IdempotencyResult{}, domain.ErrInvalidCredentials
	}

	delete(repository.refreshTokens, string(params.PreviousTokenHash))
	for hash, activeDeviceID := range repository.accessTokens {
		if activeDeviceID == params.DeviceID {
			delete(repository.accessTokens, hash)
		}
	}
	repository.accessTokens[string(params.AccessTokenHash)] = params.DeviceID
	repository.refreshTokens[string(params.RefreshTokenHash)] = params.DeviceID
	repository.storeIdempotency(params.IdempotencyRecord)
	return IdempotencyResult{EncryptedResponse: params.IdempotencyRecord.EncryptedResponse}, nil
}

func (repository *memoryRepository) DeviceIDByAccessToken(
	_ context.Context,
	accessTokenHash []byte,
	_ time.Time,
) (string, error) {
	deviceID, found := repository.accessTokens[string(accessTokenHash)]
	if !found || !repository.devices[deviceID] {
		return "", domain.ErrInvalidCredentials
	}
	return deviceID, nil
}

func (repository *memoryRepository) DeleteDevice(_ context.Context, deviceID string) error {
	if !repository.devices[deviceID] {
		return domain.ErrDeviceNotFound
	}
	delete(repository.devices, deviceID)
	return nil
}

func (repository *memoryRepository) replay(record IdempotencyRecord) (IdempotencyResult, bool, error) {
	stored, found := repository.idempotency[record.Scope+"\x00"+record.Key]
	if !found {
		return IdempotencyResult{}, false, nil
	}
	if !bytes.Equal(stored.requestHash, record.RequestHash) {
		return IdempotencyResult{}, true, domain.ErrIdempotencyConflict
	}
	return IdempotencyResult{EncryptedResponse: stored.response}, true, nil
}

func (repository *memoryRepository) storeIdempotency(record IdempotencyRecord) {
	repository.idempotency[record.Scope+"\x00"+record.Key] = memoryIdempotency{
		requestHash: append([]byte(nil), record.RequestHash...),
		response:    append([]byte(nil), record.EncryptedResponse...),
	}
}
