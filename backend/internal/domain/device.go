// Created by Rodion Kholodov.

package domain

import (
	"errors"
	"time"
)

var (
	ErrInvalidInput        = errors.New("input is invalid")
	ErrIdempotencyConflict = errors.New("idempotency key was used with another request")
	ErrInvalidCredentials  = errors.New("credentials are invalid or expired")
	ErrDeviceNotFound      = errors.New("device was not found")
)

type DeviceSession struct {
	DeviceID     string
	AccessToken  string
	RefreshToken string
	ExpiresAt    time.Time
}
