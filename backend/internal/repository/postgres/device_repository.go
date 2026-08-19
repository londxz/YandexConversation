// Created by Rodion Kholodov.

package postgres

import (
	"context"
	"crypto/subtle"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/londxz/HackatonYandex/backend/internal/domain"
	deviceusecase "github.com/londxz/HackatonYandex/backend/internal/usecase/devices"
)

type DeviceRepository struct {
	pool *pgxpool.Pool
}

func NewDeviceRepository(pool *pgxpool.Pool) *DeviceRepository {
	return &DeviceRepository{pool: pool}
}

func (repository *DeviceRepository) CreateDevice(
	ctx context.Context,
	params deviceusecase.CreateDeviceParams,
) (deviceusecase.IdempotencyResult, error) {
	tx, err := repository.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return deviceusecase.IdempotencyResult{}, fmt.Errorf("begin device registration transaction: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	result, claimed, err := claimIdempotency(ctx, tx, params.IdempotencyRecord, params.CreatedAt)
	if err != nil {
		return deviceusecase.IdempotencyResult{}, err
	}
	if !claimed {
		if err := tx.Commit(ctx); err != nil {
			return deviceusecase.IdempotencyResult{}, fmt.Errorf("commit registration replay: %w", err)
		}
		return result, nil
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO devices (id, platform, app_version, locale, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $5)
	`, params.DeviceID, params.Platform, params.AppVersion, params.Locale, params.CreatedAt); err != nil {
		return deviceusecase.IdempotencyResult{}, fmt.Errorf("insert device: %w", err)
	}

	if err := insertSession(ctx, tx, sessionRecord{
		ID:               params.SessionID,
		DeviceID:         params.DeviceID,
		AccessTokenHash:  params.AccessTokenHash,
		RefreshTokenHash: params.RefreshTokenHash,
		AccessExpiresAt:  params.AccessExpiresAt,
		RefreshExpiresAt: params.RefreshExpiresAt,
		CreatedAt:        params.CreatedAt,
	}); err != nil {
		return deviceusecase.IdempotencyResult{}, err
	}

	if err := tx.Commit(ctx); err != nil {
		return deviceusecase.IdempotencyResult{}, fmt.Errorf("commit device registration: %w", err)
	}
	return result, nil
}

func (repository *DeviceRepository) RotateSession(
	ctx context.Context,
	params deviceusecase.RotateSessionParams,
) (deviceusecase.IdempotencyResult, error) {
	tx, err := repository.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return deviceusecase.IdempotencyResult{}, fmt.Errorf("begin session rotation transaction: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	result, claimed, err := claimIdempotency(ctx, tx, params.IdempotencyRecord, params.CreatedAt)
	if err != nil {
		return deviceusecase.IdempotencyResult{}, err
	}
	if !claimed {
		if err := tx.Commit(ctx); err != nil {
			return deviceusecase.IdempotencyResult{}, fmt.Errorf("commit refresh replay: %w", err)
		}
		return result, nil
	}

	commandTag, err := tx.Exec(ctx, `
		UPDATE device_sessions
		SET revoked_at = $1
		WHERE device_id = $2
		  AND refresh_token_hash = $3
		  AND revoked_at IS NULL
		  AND refresh_expires_at > $1
	`, params.CreatedAt, params.DeviceID, params.PreviousTokenHash)
	if err != nil {
		return deviceusecase.IdempotencyResult{}, fmt.Errorf("revoke previous device session: %w", err)
	}
	if commandTag.RowsAffected() != 1 {
		return deviceusecase.IdempotencyResult{}, domain.ErrInvalidCredentials
	}

	if err := insertSession(ctx, tx, sessionRecord{
		ID:               params.SessionID,
		DeviceID:         params.DeviceID,
		AccessTokenHash:  params.AccessTokenHash,
		RefreshTokenHash: params.RefreshTokenHash,
		AccessExpiresAt:  params.AccessExpiresAt,
		RefreshExpiresAt: params.RefreshExpiresAt,
		CreatedAt:        params.CreatedAt,
	}); err != nil {
		return deviceusecase.IdempotencyResult{}, err
	}

	if err := tx.Commit(ctx); err != nil {
		return deviceusecase.IdempotencyResult{}, fmt.Errorf("commit session rotation: %w", err)
	}
	return result, nil
}

func (repository *DeviceRepository) DeviceIDByAccessToken(
	ctx context.Context,
	accessTokenHash []byte,
	now time.Time,
) (string, error) {
	var deviceID string
	err := repository.pool.QueryRow(ctx, `
		SELECT device_id
		FROM device_sessions
		WHERE access_token_hash = $1
		  AND revoked_at IS NULL
		  AND access_expires_at > $2
	`, accessTokenHash, now).Scan(&deviceID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", domain.ErrInvalidCredentials
	}
	if err != nil {
		return "", fmt.Errorf("find device session by access token: %w", err)
	}
	return deviceID, nil
}

func (repository *DeviceRepository) DeleteDevice(ctx context.Context, deviceID string) error {
	commandTag, err := repository.pool.Exec(ctx, `DELETE FROM devices WHERE id = $1`, deviceID)
	if err != nil {
		return fmt.Errorf("delete device: %w", err)
	}
	if commandTag.RowsAffected() != 1 {
		return domain.ErrDeviceNotFound
	}
	return nil
}

func claimIdempotency(
	ctx context.Context,
	tx pgx.Tx,
	record deviceusecase.IdempotencyRecord,
	now time.Time,
) (deviceusecase.IdempotencyResult, bool, error) {
	if _, err := tx.Exec(ctx, `
		DELETE FROM idempotency_keys
		WHERE scope = $1 AND key = $2 AND expires_at <= $3
	`, record.Scope, record.Key, now); err != nil {
		return deviceusecase.IdempotencyResult{}, false, fmt.Errorf("delete expired idempotency key: %w", err)
	}

	commandTag, err := tx.Exec(ctx, `
		INSERT INTO idempotency_keys (
			scope, key, owner_device_id, request_hash, response_status, response_headers,
			response_body, created_at, expires_at
		)
		VALUES ($1, $2, $3, $4, $5, '{}'::jsonb, $6, $7, $8)
		ON CONFLICT (scope, key) DO NOTHING
	`, record.Scope, record.Key, record.OwnerDeviceID, record.RequestHash, record.ResponseStatus,
		record.EncryptedResponse, now, record.ExpiresAt)
	if err != nil {
		return deviceusecase.IdempotencyResult{}, false, fmt.Errorf("claim idempotency key: %w", err)
	}
	if commandTag.RowsAffected() == 1 {
		return deviceusecase.IdempotencyResult{EncryptedResponse: record.EncryptedResponse}, true, nil
	}

	var storedRequestHash []byte
	var storedResponse []byte
	if err := tx.QueryRow(ctx, `
		SELECT request_hash, response_body
		FROM idempotency_keys
		WHERE scope = $1 AND key = $2
	`, record.Scope, record.Key).Scan(&storedRequestHash, &storedResponse); err != nil {
		return deviceusecase.IdempotencyResult{}, false, fmt.Errorf("read idempotency replay: %w", err)
	}
	if subtle.ConstantTimeCompare(storedRequestHash, record.RequestHash) != 1 {
		return deviceusecase.IdempotencyResult{}, false, domain.ErrIdempotencyConflict
	}
	if len(storedResponse) == 0 {
		return deviceusecase.IdempotencyResult{}, false, errors.New("idempotency replay response is empty")
	}
	return deviceusecase.IdempotencyResult{EncryptedResponse: storedResponse}, false, nil
}

type sessionRecord struct {
	ID               string
	DeviceID         string
	AccessTokenHash  []byte
	RefreshTokenHash []byte
	AccessExpiresAt  time.Time
	RefreshExpiresAt time.Time
	CreatedAt        time.Time
}

func insertSession(ctx context.Context, tx pgx.Tx, record sessionRecord) error {
	if _, err := tx.Exec(ctx, `
		INSERT INTO device_sessions (
			id, device_id, access_token_hash, refresh_token_hash,
			access_expires_at, refresh_expires_at, created_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, record.ID, record.DeviceID, record.AccessTokenHash, record.RefreshTokenHash,
		record.AccessExpiresAt, record.RefreshExpiresAt, record.CreatedAt); err != nil {
		return fmt.Errorf("insert device session: %w", err)
	}
	return nil
}
