// Created by Rodion Kholodov.

package devices

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"time"

	"golang.org/x/text/language"

	"github.com/londxz/HackatonYandex/backend/internal/domain"
	"github.com/londxz/HackatonYandex/backend/internal/security"
)

const (
	registerScope = "devices.register"
	refreshScope  = "devices.refresh"
)

var appVersionPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$`)

type Repository interface {
	CreateDevice(context.Context, CreateDeviceParams) (IdempotencyResult, error)
	RotateSession(context.Context, RotateSessionParams) (IdempotencyResult, error)
	DeviceIDByAccessToken(context.Context, []byte, time.Time) (string, error)
	DeleteDevice(context.Context, string) error
}

type CreateDeviceParams struct {
	DeviceID          string
	SessionID         string
	Platform          string
	AppVersion        string
	Locale            string
	AccessTokenHash   []byte
	RefreshTokenHash  []byte
	AccessExpiresAt   time.Time
	RefreshExpiresAt  time.Time
	CreatedAt         time.Time
	IdempotencyRecord IdempotencyRecord
}

type RotateSessionParams struct {
	DeviceID          string
	SessionID         string
	PreviousTokenHash []byte
	AccessTokenHash   []byte
	RefreshTokenHash  []byte
	AccessExpiresAt   time.Time
	RefreshExpiresAt  time.Time
	CreatedAt         time.Time
	IdempotencyRecord IdempotencyRecord
}

type IdempotencyRecord struct {
	Scope             string
	Key               string
	OwnerDeviceID     string
	RequestHash       []byte
	EncryptedResponse []byte
	ResponseStatus    int
	ExpiresAt         time.Time
}

type IdempotencyResult struct {
	EncryptedResponse []byte
}

type RegisterInput struct {
	Platform   string
	AppVersion string
	Locale     string
}

type RefreshInput struct {
	DeviceID     string
	RefreshToken string
}

type Service struct {
	repository  Repository
	credentials *security.CredentialManager
	sealer      *security.Sealer
	policy      SessionPolicy
	now         func() time.Time
}

type SessionPolicy struct {
	AccessTokenTTL  time.Duration
	RefreshTokenTTL time.Duration
	IdempotencyTTL  time.Duration
}

func NewService(
	repository Repository,
	credentials *security.CredentialManager,
	sealer *security.Sealer,
	policy SessionPolicy,
) *Service {
	return &Service{
		repository:  repository,
		credentials: credentials,
		sealer:      sealer,
		policy:      policy,
		now:         time.Now,
	}
}

func (service *Service) Register(
	ctx context.Context,
	input RegisterInput,
	idempotencyKey string,
) (domain.DeviceSession, error) {
	input.Platform = strings.TrimSpace(input.Platform)
	input.AppVersion = strings.TrimSpace(input.AppVersion)
	input.Locale = strings.TrimSpace(input.Locale)
	if err := validateRegistration(input, idempotencyKey); err != nil {
		return domain.DeviceSession{}, err
	}

	now := service.now().UTC()
	session, persistence, err := service.issueSession(now)
	if err != nil {
		return domain.DeviceSession{}, err
	}
	requestHash, err := hashJSON(struct {
		Platform   string `json:"platform"`
		AppVersion string `json:"app_version"`
		Locale     string `json:"locale"`
	}{input.Platform, input.AppVersion, input.Locale})
	if err != nil {
		return domain.DeviceSession{}, err
	}
	encryptedResponse, err := service.encryptSession(registerScope, idempotencyKey, session)
	if err != nil {
		return domain.DeviceSession{}, err
	}

	result, err := service.repository.CreateDevice(ctx, CreateDeviceParams{
		DeviceID:         session.DeviceID,
		SessionID:        persistence.sessionID,
		Platform:         input.Platform,
		AppVersion:       input.AppVersion,
		Locale:           input.Locale,
		AccessTokenHash:  persistence.accessTokenHash,
		RefreshTokenHash: persistence.refreshTokenHash,
		AccessExpiresAt:  session.ExpiresAt,
		RefreshExpiresAt: persistence.refreshExpiresAt,
		CreatedAt:        now,
		IdempotencyRecord: IdempotencyRecord{
			Scope:             registerScope,
			Key:               idempotencyKey,
			OwnerDeviceID:     session.DeviceID,
			RequestHash:       requestHash,
			EncryptedResponse: encryptedResponse,
			ResponseStatus:    201,
			ExpiresAt:         now.Add(service.policy.IdempotencyTTL),
		},
	})
	if err != nil {
		return domain.DeviceSession{}, err
	}
	return service.decryptSession(registerScope, idempotencyKey, result.EncryptedResponse)
}

func (service *Service) Refresh(
	ctx context.Context,
	input RefreshInput,
	idempotencyKey string,
) (domain.DeviceSession, error) {
	input.DeviceID = strings.TrimSpace(input.DeviceID)
	input.RefreshToken = strings.TrimSpace(input.RefreshToken)
	if !security.IsUUID(input.DeviceID) {
		return domain.DeviceSession{}, fmt.Errorf("%w: device_id must be a UUID", domain.ErrInvalidInput)
	}
	if !service.credentials.IsRefreshToken(input.RefreshToken) {
		return domain.DeviceSession{}, domain.ErrInvalidCredentials
	}
	if err := validateIdempotencyKey(idempotencyKey); err != nil {
		return domain.DeviceSession{}, err
	}

	now := service.now().UTC()
	session, persistence, err := service.issueSessionForDevice(input.DeviceID, now)
	if err != nil {
		return domain.DeviceSession{}, err
	}
	previousTokenHash := service.credentials.HashToken(input.RefreshToken)
	requestHash, err := hashJSON(struct {
		DeviceID         string `json:"device_id"`
		RefreshTokenHash []byte `json:"refresh_token_hash"`
	}{input.DeviceID, previousTokenHash})
	if err != nil {
		return domain.DeviceSession{}, err
	}
	encryptedResponse, err := service.encryptSession(refreshScope, idempotencyKey, session)
	if err != nil {
		return domain.DeviceSession{}, err
	}

	result, err := service.repository.RotateSession(ctx, RotateSessionParams{
		DeviceID:          input.DeviceID,
		SessionID:         persistence.sessionID,
		PreviousTokenHash: previousTokenHash,
		AccessTokenHash:   persistence.accessTokenHash,
		RefreshTokenHash:  persistence.refreshTokenHash,
		AccessExpiresAt:   session.ExpiresAt,
		RefreshExpiresAt:  persistence.refreshExpiresAt,
		CreatedAt:         now,
		IdempotencyRecord: IdempotencyRecord{
			Scope:             refreshScope,
			Key:               idempotencyKey,
			OwnerDeviceID:     input.DeviceID,
			RequestHash:       requestHash,
			EncryptedResponse: encryptedResponse,
			ResponseStatus:    200,
			ExpiresAt:         now.Add(service.policy.IdempotencyTTL),
		},
	})
	if err != nil {
		return domain.DeviceSession{}, err
	}
	return service.decryptSession(refreshScope, idempotencyKey, result.EncryptedResponse)
}

func (service *Service) Authenticate(ctx context.Context, accessToken string) (string, error) {
	accessToken = strings.TrimSpace(accessToken)
	if !service.credentials.IsAccessToken(accessToken) {
		return "", domain.ErrInvalidCredentials
	}

	deviceID, err := service.repository.DeviceIDByAccessToken(
		ctx,
		service.credentials.HashToken(accessToken),
		service.now().UTC(),
	)
	if err != nil {
		return "", err
	}
	return deviceID, nil
}

func (service *Service) Delete(ctx context.Context, deviceID string) error {
	if !security.IsUUID(deviceID) {
		return fmt.Errorf("%w: device_id must be a UUID", domain.ErrInvalidInput)
	}
	return service.repository.DeleteDevice(ctx, deviceID)
}

type sessionPersistence struct {
	sessionID        string
	accessTokenHash  []byte
	refreshTokenHash []byte
	refreshExpiresAt time.Time
}

func (service *Service) issueSession(now time.Time) (domain.DeviceSession, sessionPersistence, error) {
	deviceID, err := security.NewUUID()
	if err != nil {
		return domain.DeviceSession{}, sessionPersistence{}, err
	}
	return service.issueSessionForDevice(deviceID, now)
}

func (service *Service) issueSessionForDevice(deviceID string, now time.Time) (domain.DeviceSession, sessionPersistence, error) {
	sessionID, err := security.NewUUID()
	if err != nil {
		return domain.DeviceSession{}, sessionPersistence{}, err
	}
	accessToken, accessHash, err := service.credentials.NewAccessToken()
	if err != nil {
		return domain.DeviceSession{}, sessionPersistence{}, err
	}
	refreshToken, refreshHash, err := service.credentials.NewRefreshToken()
	if err != nil {
		return domain.DeviceSession{}, sessionPersistence{}, err
	}

	return domain.DeviceSession{
			DeviceID:     deviceID,
			AccessToken:  accessToken,
			RefreshToken: refreshToken,
			ExpiresAt:    now.Add(service.policy.AccessTokenTTL),
		}, sessionPersistence{
			sessionID:        sessionID,
			accessTokenHash:  accessHash,
			refreshTokenHash: refreshHash,
			refreshExpiresAt: now.Add(service.policy.RefreshTokenTTL),
		}, nil
}

func (service *Service) encryptSession(scope string, key string, session domain.DeviceSession) ([]byte, error) {
	encoded, err := json.Marshal(sessionReplay{
		DeviceID:     session.DeviceID,
		AccessToken:  session.AccessToken,
		RefreshToken: session.RefreshToken,
		ExpiresAt:    session.ExpiresAt,
	})
	if err != nil {
		return nil, fmt.Errorf("encode device session replay: %w", err)
	}
	sealed, err := service.sealer.Seal(encoded, idempotencyAssociatedData(scope, key))
	if err != nil {
		return nil, fmt.Errorf("encrypt device session replay: %w", err)
	}
	return sealed, nil
}

func (service *Service) decryptSession(scope string, key string, encrypted []byte) (domain.DeviceSession, error) {
	plaintext, err := service.sealer.Open(encrypted, idempotencyAssociatedData(scope, key))
	if err != nil {
		return domain.DeviceSession{}, fmt.Errorf("decrypt device session replay: %w", err)
	}

	var replay sessionReplay
	if err := json.Unmarshal(plaintext, &replay); err != nil {
		return domain.DeviceSession{}, fmt.Errorf("decode device session replay: %w", err)
	}
	return domain.DeviceSession{
		DeviceID:     replay.DeviceID,
		AccessToken:  replay.AccessToken,
		RefreshToken: replay.RefreshToken,
		ExpiresAt:    replay.ExpiresAt,
	}, nil
}

type sessionReplay struct {
	DeviceID     string    `json:"device_id"`
	AccessToken  string    `json:"access_token"`
	RefreshToken string    `json:"refresh_token"`
	ExpiresAt    time.Time `json:"expires_at"`
}

func validateRegistration(input RegisterInput, idempotencyKey string) error {
	if input.Platform != "ios" {
		return fmt.Errorf("%w: platform must be ios", domain.ErrInvalidInput)
	}
	if !appVersionPattern.MatchString(input.AppVersion) {
		return fmt.Errorf("%w: app_version is invalid", domain.ErrInvalidInput)
	}
	if len(input.Locale) < 2 || len(input.Locale) > 35 {
		return fmt.Errorf("%w: locale is invalid", domain.ErrInvalidInput)
	}
	if _, err := language.Parse(input.Locale); err != nil {
		return fmt.Errorf("%w: locale is invalid", domain.ErrInvalidInput)
	}
	return validateIdempotencyKey(idempotencyKey)
}

func validateIdempotencyKey(key string) error {
	if len(key) < 16 || len(key) > 100 {
		return fmt.Errorf("%w: Idempotency-Key must contain 16 to 100 characters", domain.ErrInvalidInput)
	}
	for _, character := range key {
		if character < 0x21 || character > 0x7e {
			return fmt.Errorf("%w: Idempotency-Key must contain visible ASCII characters", domain.ErrInvalidInput)
		}
	}
	return nil
}

func hashJSON(value any) ([]byte, error) {
	encoded, err := json.Marshal(value)
	if err != nil {
		return nil, fmt.Errorf("encode request hash input: %w", err)
	}
	hash := sha256.Sum256(encoded)
	return hash[:], nil
}

func idempotencyAssociatedData(scope string, key string) []byte {
	return []byte(scope + "\x00" + key)
}
