// Created by Rodion Kholodov.

package config

import (
	"testing"
	"time"
)

func TestLoadUsesProductionDefaults(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	setTestSecrets(t)
	t.Setenv("APP_ENV", "")
	t.Setenv("HTTP_ADDRESS", "")
	t.Setenv("HTTP_MAX_BODY_BYTES", "")

	config, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if config.Environment != "development" {
		t.Fatalf("Environment = %q, want development", config.Environment)
	}
	if config.HTTP.Address != ":8080" {
		t.Fatalf("HTTP address = %q, want :8080", config.HTTP.Address)
	}
	if config.HTTP.MaxBodyBytes != 25<<20 {
		t.Fatalf("MaxBodyBytes = %d, want %d", config.HTTP.MaxBodyBytes, 25<<20)
	}
	if config.Database.HealthTimeout != 2*time.Second {
		t.Fatalf("HealthTimeout = %s, want 2s", config.Database.HealthTimeout)
	}
	if config.Speech.Provider != "disabled" {
		t.Fatalf("Speech provider = %q, want disabled", config.Speech.Provider)
	}
	if config.Speech.MaxAudioBytes != 1<<20 || config.Speech.MaxDuration != 30*time.Second {
		t.Fatalf("Speech limits = %d bytes, %s", config.Speech.MaxAudioBytes, config.Speech.MaxDuration)
	}
}

func TestLoadRejectsMissingDatabaseURL(t *testing.T) {
	t.Setenv("DATABASE_URL", "")
	setTestSecrets(t)

	_, err := Load()
	if err == nil {
		t.Fatal("Load() error = nil, want validation error")
	}
}

func TestLoadRejectsInvalidDuration(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	setTestSecrets(t)
	t.Setenv("HTTP_READ_TIMEOUT", "later")

	_, err := Load()
	if err == nil {
		t.Fatal("Load() error = nil, want duration error")
	}
}

func TestLoadRejectsInvalidPoolBounds(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	setTestSecrets(t)
	t.Setenv("DATABASE_MIN_CONNECTIONS", "5")
	t.Setenv("DATABASE_MAX_CONNECTIONS", "2")

	_, err := Load()
	if err == nil {
		t.Fatal("Load() error = nil, want pool validation error")
	}
}

func TestLoadRejectsMissingTokenPepper(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	t.Setenv("TOKEN_PEPPER_BASE64", "")
	t.Setenv("IDEMPOTENCY_ENCRYPTION_KEY_BASE64", "bG9jYWwtaWRlbXBvdGVuY3ktMzItYnl0ZS12YWx1ZXM=")

	_, err := Load()
	if err == nil {
		t.Fatal("Load() error = nil, want missing secret error")
	}
}

func TestLoadRejectsRefreshTTLShorterThanAccessTTL(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	setTestSecrets(t)
	t.Setenv("ACCESS_TOKEN_TTL", "2h")
	t.Setenv("REFRESH_TOKEN_TTL", "1h")

	_, err := Load()
	if err == nil {
		t.Fatal("Load() error = nil, want token TTL validation error")
	}
}

func TestLoadRequiresSpeechProviderInProduction(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	setTestSecrets(t)
	t.Setenv("APP_ENV", "production")

	_, err := Load()
	if err == nil {
		t.Fatal("Load() error = nil, want disabled production speech error")
	}
}

func TestLoadRequiresYandexAPIKey(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	setTestSecrets(t)
	t.Setenv("SPEECH_PROVIDER", "yandex")
	t.Setenv("YANDEX_SPEECHKIT_API_KEY", "")

	_, err := Load()
	if err == nil {
		t.Fatal("Load() error = nil, want missing SpeechKit API key error")
	}
}

func TestLoadAcceptsConfiguredYandexProvider(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	setTestSecrets(t)
	t.Setenv("SPEECH_PROVIDER", "yandex")
	t.Setenv("YANDEX_SPEECHKIT_API_KEY", "secret-api-key")

	config, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if config.Speech.Provider != "yandex" || config.Speech.YandexAPIKey != "secret-api-key" {
		t.Fatalf("Speech config = %#v", config.Speech)
	}
}

func setTestSecrets(t *testing.T) {
	t.Helper()
	t.Setenv("TOKEN_PEPPER_BASE64", "bG9jYWwtdG9rZW4tcGVwcGVyLTMyLWJ5dGUtdmFsdWU=")
	t.Setenv("IDEMPOTENCY_ENCRYPTION_KEY_BASE64", "bG9jYWwtaWRlbXBvdGVuY3ktMzItYnl0ZS12YWx1ZXM=")
	t.Setenv("SPEECH_PROVIDER", "")
	t.Setenv("SPEECH_SUPPORTED_LANGUAGES", "")
	t.Setenv("YANDEX_SPEECHKIT_ENDPOINT", "")
	t.Setenv("YANDEX_SPEECHKIT_API_KEY", "")
}
