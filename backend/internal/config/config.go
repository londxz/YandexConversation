// Created by Rodion Kholodov.

package config

import (
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Environment     string
	LogLevel        string
	ShutdownTimeout time.Duration
	HTTP            HTTPConfig
	Database        DatabaseConfig
	DeviceSessions  DeviceSessionConfig
	Secrets         SecretsConfig
}

type HTTPConfig struct {
	Address           string
	ReadHeaderTimeout time.Duration
	ReadTimeout       time.Duration
	WriteTimeout      time.Duration
	IdleTimeout       time.Duration
	MaxBodyBytes      int64
}

type DatabaseConfig struct {
	URL             string
	ConnectTimeout  time.Duration
	HealthTimeout   time.Duration
	MaxConnections  int32
	MinConnections  int32
	MaxConnLifetime time.Duration
	MaxConnIdleTime time.Duration
}

type DeviceSessionConfig struct {
	AccessTokenTTL  time.Duration
	RefreshTokenTTL time.Duration
	IdempotencyTTL  time.Duration
}

type SecretsConfig struct {
	TokenPepper              []byte
	IdempotencyEncryptionKey []byte
}

func Load() (Config, error) {
	config := Config{
		Environment:     valueOrDefault("APP_ENV", "development"),
		LogLevel:        valueOrDefault("LOG_LEVEL", "info"),
		ShutdownTimeout: 10 * time.Second,
		HTTP: HTTPConfig{
			Address:           valueOrDefault("HTTP_ADDRESS", ":8080"),
			ReadHeaderTimeout: 5 * time.Second,
			ReadTimeout:       30 * time.Second,
			WriteTimeout:      30 * time.Second,
			IdleTimeout:       60 * time.Second,
			MaxBodyBytes:      25 << 20,
		},
		Database: DatabaseConfig{
			URL:             strings.TrimSpace(os.Getenv("DATABASE_URL")),
			ConnectTimeout:  5 * time.Second,
			HealthTimeout:   2 * time.Second,
			MaxConnections:  20,
			MinConnections:  2,
			MaxConnLifetime: 30 * time.Minute,
			MaxConnIdleTime: 5 * time.Minute,
		},
		DeviceSessions: DeviceSessionConfig{
			AccessTokenTTL:  15 * time.Minute,
			RefreshTokenTTL: 90 * 24 * time.Hour,
			IdempotencyTTL:  24 * time.Hour,
		},
	}

	var err error
	if config.ShutdownTimeout, err = duration("SHUTDOWN_TIMEOUT", config.ShutdownTimeout); err != nil {
		return Config{}, err
	}
	if config.HTTP.ReadHeaderTimeout, err = duration("HTTP_READ_HEADER_TIMEOUT", config.HTTP.ReadHeaderTimeout); err != nil {
		return Config{}, err
	}
	if config.HTTP.ReadTimeout, err = duration("HTTP_READ_TIMEOUT", config.HTTP.ReadTimeout); err != nil {
		return Config{}, err
	}
	if config.HTTP.WriteTimeout, err = duration("HTTP_WRITE_TIMEOUT", config.HTTP.WriteTimeout); err != nil {
		return Config{}, err
	}
	if config.HTTP.IdleTimeout, err = duration("HTTP_IDLE_TIMEOUT", config.HTTP.IdleTimeout); err != nil {
		return Config{}, err
	}
	if config.HTTP.MaxBodyBytes, err = positiveInt64("HTTP_MAX_BODY_BYTES", config.HTTP.MaxBodyBytes); err != nil {
		return Config{}, err
	}
	if config.Database.ConnectTimeout, err = duration("DATABASE_CONNECT_TIMEOUT", config.Database.ConnectTimeout); err != nil {
		return Config{}, err
	}
	if config.Database.HealthTimeout, err = duration("DATABASE_HEALTH_TIMEOUT", config.Database.HealthTimeout); err != nil {
		return Config{}, err
	}
	if config.Database.MaxConnLifetime, err = duration("DATABASE_MAX_CONN_LIFETIME", config.Database.MaxConnLifetime); err != nil {
		return Config{}, err
	}
	if config.Database.MaxConnIdleTime, err = duration("DATABASE_MAX_CONN_IDLE_TIME", config.Database.MaxConnIdleTime); err != nil {
		return Config{}, err
	}
	if config.Database.MaxConnections, err = positiveInt32("DATABASE_MAX_CONNECTIONS", config.Database.MaxConnections); err != nil {
		return Config{}, err
	}
	if config.Database.MinConnections, err = nonNegativeInt32("DATABASE_MIN_CONNECTIONS", config.Database.MinConnections); err != nil {
		return Config{}, err
	}
	if config.DeviceSessions.AccessTokenTTL, err = duration("ACCESS_TOKEN_TTL", config.DeviceSessions.AccessTokenTTL); err != nil {
		return Config{}, err
	}
	if config.DeviceSessions.RefreshTokenTTL, err = duration("REFRESH_TOKEN_TTL", config.DeviceSessions.RefreshTokenTTL); err != nil {
		return Config{}, err
	}
	if config.DeviceSessions.IdempotencyTTL, err = duration("IDEMPOTENCY_TTL", config.DeviceSessions.IdempotencyTTL); err != nil {
		return Config{}, err
	}
	if config.Secrets.TokenPepper, err = secret("TOKEN_PEPPER_BASE64"); err != nil {
		return Config{}, err
	}
	if config.Secrets.IdempotencyEncryptionKey, err = secret("IDEMPOTENCY_ENCRYPTION_KEY_BASE64"); err != nil {
		return Config{}, err
	}

	if err := config.validate(); err != nil {
		return Config{}, err
	}

	return config, nil
}

func (config Config) validate() error {
	validEnvironments := map[string]bool{
		"development": true,
		"staging":     true,
		"production":  true,
		"test":        true,
	}
	if !validEnvironments[config.Environment] {
		return fmt.Errorf("APP_ENV must be development, staging, production, or test")
	}

	validLogLevels := map[string]bool{
		"debug": true,
		"info":  true,
		"warn":  true,
		"error": true,
	}
	if !validLogLevels[config.LogLevel] {
		return fmt.Errorf("LOG_LEVEL must be debug, info, warn, or error")
	}

	if config.HTTP.Address == "" {
		return errors.New("HTTP_ADDRESS is required")
	}
	if config.Database.URL == "" {
		return errors.New("DATABASE_URL is required")
	}
	if config.Database.MinConnections > config.Database.MaxConnections {
		return errors.New("DATABASE_MIN_CONNECTIONS cannot exceed DATABASE_MAX_CONNECTIONS")
	}
	if config.DeviceSessions.RefreshTokenTTL <= config.DeviceSessions.AccessTokenTTL {
		return errors.New("REFRESH_TOKEN_TTL must exceed ACCESS_TOKEN_TTL")
	}

	return nil
}

func secret(key string) ([]byte, error) {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return nil, fmt.Errorf("%s is required", key)
	}

	decoded, err := base64.StdEncoding.DecodeString(value)
	if err != nil || len(decoded) != 32 {
		return nil, fmt.Errorf("%s must be standard base64 encoding exactly 32 bytes", key)
	}
	return decoded, nil
}

func valueOrDefault(key string, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func duration(key string, fallback time.Duration) (time.Duration, error) {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback, nil
	}

	parsed, err := time.ParseDuration(value)
	if err != nil || parsed <= 0 {
		return 0, fmt.Errorf("%s must be a positive duration", key)
	}
	return parsed, nil
}

func positiveInt64(key string, fallback int64) (int64, error) {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback, nil
	}

	parsed, err := strconv.ParseInt(value, 10, 64)
	if err != nil || parsed <= 0 {
		return 0, fmt.Errorf("%s must be a positive integer", key)
	}
	return parsed, nil
}

func positiveInt32(key string, fallback int32) (int32, error) {
	value, err := positiveInt64(key, int64(fallback))
	if err != nil {
		return 0, err
	}
	if value > int64(^uint32(0)>>1) {
		return 0, fmt.Errorf("%s is too large", key)
	}
	return int32(value), nil
}

func nonNegativeInt32(key string, fallback int32) (int32, error) {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback, nil
	}

	parsed, err := strconv.ParseInt(value, 10, 32)
	if err != nil || parsed < 0 {
		return 0, fmt.Errorf("%s must be a non-negative integer", key)
	}
	return int32(parsed), nil
}
