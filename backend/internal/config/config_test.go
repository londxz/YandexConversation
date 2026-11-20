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
	if config.Speech.WhisperEndpoint != "http://127.0.0.1:8081/inference" {
		t.Fatalf("Whisper endpoint = %q", config.Speech.WhisperEndpoint)
	}
	if config.Speech.MaxAudioBytes != 1<<20 || config.Speech.MaxDuration != 30*time.Second {
		t.Fatalf("Speech limits = %d bytes, %s", config.Speech.MaxAudioBytes, config.Speech.MaxDuration)
	}
	if config.Speech.StreamPartialInterval != 2*time.Second ||
		config.Speech.StreamSilenceDuration != 800*time.Millisecond ||
		config.Speech.StreamMaxSegmentDuration != 15*time.Second {
		t.Fatalf("unexpected speech stream timing: %#v", config.Speech)
	}
	if config.Diarization.Provider != "disabled" ||
		config.Diarization.SimilarityThreshold != 0.72 ||
		config.Diarization.MinimumAudio != time.Second {
		t.Fatalf("unexpected diarization defaults: %#v", config.Diarization)
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

func TestLoadAllowsDisabledSpeechProviderInProduction(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	setTestSecrets(t)
	t.Setenv("APP_ENV", "production")

	config, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if config.Speech.Provider != "disabled" {
		t.Fatalf("Speech provider = %q, want disabled", config.Speech.Provider)
	}
}

func TestLoadAllowsConfiguredWhisperProvider(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	setTestSecrets(t)
	t.Setenv("SPEECH_PROVIDER", "whisper")
	t.Setenv("WHISPER_ENDPOINT", "http://whisper:8080/inference")

	config, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if config.Speech.Provider != "whisper" {
		t.Fatalf("Speech provider = %q, want whisper", config.Speech.Provider)
	}
}

func TestLoadRejectsUnknownSpeechProvider(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	setTestSecrets(t)
	t.Setenv("SPEECH_PROVIDER", "cloud")

	_, err := Load()
	if err == nil {
		t.Fatal("Load() error = nil, want unsupported provider error")
	}
}

func TestLoadRejectsInvalidWhisperEndpoint(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	setTestSecrets(t)
	t.Setenv("SPEECH_PROVIDER", "whisper")
	t.Setenv("WHISPER_ENDPOINT", "whisper:8080")

	_, err := Load()
	if err == nil {
		t.Fatal("Load() error = nil, want invalid endpoint error")
	}
}

func TestLoadRejectsStreamSegmentLongerThanBatchLimit(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	setTestSecrets(t)
	t.Setenv("SPEECH_STREAM_MAX_SEGMENT_DURATION", "31s")

	_, err := Load()
	if err == nil {
		t.Fatal("Load() error = nil, want stream duration validation error")
	}
}

func TestLoadAllowsConfiguredSherpaDiarization(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	setTestSecrets(t)
	t.Setenv("DIARIZATION_PROVIDER", "sherpa")
	t.Setenv("SPEAKER_EMBEDDING_ENDPOINT", "http://speaker-embedder:8090/v1/embedding")
	t.Setenv("DIARIZATION_SIMILARITY_THRESHOLD", "0.81")

	config, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if config.Diarization.Provider != "sherpa" || config.Diarization.SimilarityThreshold != 0.81 {
		t.Fatalf("Diarization config = %#v", config.Diarization)
	}
}

func TestLoadRejectsInvalidDiarizationConfiguration(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:password@localhost:5432/razgovor")
	setTestSecrets(t)
	t.Setenv("DIARIZATION_PROVIDER", "sherpa")
	t.Setenv("SPEAKER_EMBEDDING_ENDPOINT", "speaker-embedder:8090")

	if _, err := Load(); err == nil {
		t.Fatal("Load() error = nil, want invalid diarization endpoint error")
	}

	t.Setenv("SPEAKER_EMBEDDING_ENDPOINT", "http://speaker-embedder:8090/v1/embedding")
	t.Setenv("DIARIZATION_SIMILARITY_THRESHOLD", "1.2")
	if _, err := Load(); err == nil {
		t.Fatal("Load() error = nil, want invalid similarity threshold error")
	}
}

func setTestSecrets(t *testing.T) {
	t.Helper()
	t.Setenv("TOKEN_PEPPER_BASE64", "bG9jYWwtdG9rZW4tcGVwcGVyLTMyLWJ5dGUtdmFsdWU=")
	t.Setenv("IDEMPOTENCY_ENCRYPTION_KEY_BASE64", "bG9jYWwtaWRlbXBvdGVuY3ktMzItYnl0ZS12YWx1ZXM=")
	t.Setenv("SPEECH_PROVIDER", "")
	t.Setenv("WHISPER_ENDPOINT", "")
	t.Setenv("SPEECH_SUPPORTED_LANGUAGES", "")
	t.Setenv("SPEECH_STREAM_PARTIAL_INTERVAL", "")
	t.Setenv("SPEECH_STREAM_SILENCE_DURATION", "")
	t.Setenv("SPEECH_STREAM_MAX_SEGMENT_DURATION", "")
	t.Setenv("SPEECH_STREAM_MAX_CHUNK_BYTES", "")
	t.Setenv("SPEECH_STREAM_MAX_CONNECTIONS", "")
	t.Setenv("DIARIZATION_PROVIDER", "")
	t.Setenv("SPEAKER_EMBEDDING_ENDPOINT", "")
	t.Setenv("DIARIZATION_TIMEOUT", "")
	t.Setenv("DIARIZATION_MIN_AUDIO_DURATION", "")
	t.Setenv("DIARIZATION_SIMILARITY_THRESHOLD", "")
	t.Setenv("DIARIZATION_MAX_SPEAKERS", "")
	t.Setenv("DIARIZATION_MAX_CONCURRENT_REQUESTS", "")
}
