// Created by Rodion Kholodov.

package speech

import (
	"context"
	"encoding/binary"
	"errors"
	"testing"
	"time"

	"github.com/londxz/HackatonYandex/backend/internal/domain"
	speechprovider "github.com/londxz/HackatonYandex/backend/internal/speech"
)

type providerStub struct {
	result    speechprovider.RecognitionResult
	err       error
	input     speechprovider.RecognitionRequest
	callCount int
	wait      bool
}

type blockingProvider struct {
	started chan struct{}
	release chan struct{}
}

func (provider *blockingProvider) Transcribe(
	context.Context,
	speechprovider.RecognitionRequest,
) (speechprovider.RecognitionResult, error) {
	close(provider.started)
	<-provider.release
	return speechprovider.RecognitionResult{Text: "готово"}, nil
}

func (stub *providerStub) Transcribe(
	ctx context.Context,
	input speechprovider.RecognitionRequest,
) (speechprovider.RecognitionResult, error) {
	stub.callCount++
	stub.input = input
	if stub.wait {
		<-ctx.Done()
		return speechprovider.RecognitionResult{}, ctx.Err()
	}
	return stub.result, stub.err
}

func TestServiceTranscribesValidatedWAV(t *testing.T) {
	confidence := 0.91
	provider := &providerStub{result: speechprovider.RecognitionResult{
		Text:       "  Здравствуйте  ",
		Confidence: &confidence,
	}}
	service := newTestService(provider)
	pcm := make([]byte, 3200)

	transcript, err := service.Transcribe(context.Background(), TranscribeInput{
		WAV:      makePCM16WAV(requiredSampleRate, requiredChannels, pcm),
		Language: "ru-RU",
	})
	if err != nil {
		t.Fatalf("Transcribe() error = %v", err)
	}

	if transcript.Text != "Здравствуйте" {
		t.Fatalf("text = %q", transcript.Text)
	}
	if transcript.Language != "ru-RU" {
		t.Fatalf("language = %q", transcript.Language)
	}
	if transcript.Duration != 100*time.Millisecond {
		t.Fatalf("duration = %s, want 100ms", transcript.Duration)
	}
	if provider.callCount != 1 {
		t.Fatalf("provider calls = %d, want 1", provider.callCount)
	}
	if len(provider.input.PCM16LittleEndian) != len(pcm) {
		t.Fatalf("provider PCM bytes = %d, want %d", len(provider.input.PCM16LittleEndian), len(pcm))
	}
	if len(provider.input.WAV) != len(pcm)+44 {
		t.Fatalf("provider WAV bytes = %d, want %d", len(provider.input.WAV), len(pcm)+44)
	}
	if provider.input.SampleRateHertz != 16000 || provider.input.Channels != 1 {
		t.Fatalf("provider format = %#v", provider.input)
	}
}

func TestServiceRejectsInvalidWAVBeforeProvider(t *testing.T) {
	provider := &providerStub{}
	service := newTestService(provider)

	_, err := service.Transcribe(context.Background(), TranscribeInput{
		WAV:      makePCM16WAV(44100, requiredChannels, make([]byte, 100)),
		Language: "ru-RU",
	})

	if !errors.Is(err, domain.ErrInvalidAudio) {
		t.Fatalf("error = %v, want ErrInvalidAudio", err)
	}
	if provider.callCount != 0 {
		t.Fatalf("provider calls = %d, want 0", provider.callCount)
	}
}

func TestServiceEnforcesAudioSizeAndDuration(t *testing.T) {
	tests := []struct {
		name        string
		policy      Policy
		pcm         []byte
		expectedErr error
	}{
		{
			name: "size",
			policy: Policy{
				RecognitionTimeout: time.Second,
				MaxAudioBytes:      100,
				MaxDuration:        30 * time.Second,
				SupportedLanguages: []string{"ru-RU"},
				MaxConcurrent:      1,
			},
			pcm:         make([]byte, 102),
			expectedErr: domain.ErrAudioTooLarge,
		},
		{
			name: "duration",
			policy: Policy{
				RecognitionTimeout: time.Second,
				MaxAudioBytes:      10_000,
				MaxDuration:        50 * time.Millisecond,
				SupportedLanguages: []string{"ru-RU"},
				MaxConcurrent:      1,
			},
			pcm:         make([]byte, 3200),
			expectedErr: domain.ErrAudioTooLong,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			provider := &providerStub{}
			service := NewService(provider, test.policy)
			_, err := service.Transcribe(context.Background(), TranscribeInput{
				WAV:      makePCM16WAV(requiredSampleRate, requiredChannels, test.pcm),
				Language: "ru-RU",
			})
			if !errors.Is(err, test.expectedErr) {
				t.Fatalf("error = %v, want %v", err, test.expectedErr)
			}
			if provider.callCount != 0 {
				t.Fatalf("provider calls = %d, want 0", provider.callCount)
			}
		})
	}
}

func TestServiceRejectsUnsupportedLanguage(t *testing.T) {
	provider := &providerStub{}
	service := newTestService(provider)

	_, err := service.Transcribe(context.Background(), TranscribeInput{Language: "de-DE"})

	if !errors.Is(err, domain.ErrUnsupportedLanguage) {
		t.Fatalf("error = %v, want ErrUnsupportedLanguage", err)
	}
	if provider.callCount != 0 {
		t.Fatalf("provider calls = %d, want 0", provider.callCount)
	}
}

func TestServiceMapsProviderFailureAndTimeout(t *testing.T) {
	t.Run("unavailable", func(t *testing.T) {
		provider := &providerStub{err: speechprovider.ErrUnavailable}
		service := newTestService(provider)
		_, err := service.Transcribe(context.Background(), TranscribeInput{
			WAV:      makePCM16WAV(requiredSampleRate, requiredChannels, make([]byte, 100)),
			Language: "ru-RU",
		})
		if !errors.Is(err, domain.ErrSpeechUnavailable) {
			t.Fatalf("error = %v, want ErrSpeechUnavailable", err)
		}
	})

	t.Run("timeout", func(t *testing.T) {
		provider := &providerStub{wait: true}
		service := NewService(provider, Policy{
			RecognitionTimeout: 5 * time.Millisecond,
			MaxAudioBytes:      1024,
			MaxDuration:        time.Second,
			SupportedLanguages: []string{"ru-RU"},
			MaxConcurrent:      1,
		})
		_, err := service.Transcribe(context.Background(), TranscribeInput{
			WAV:      makePCM16WAV(requiredSampleRate, requiredChannels, make([]byte, 100)),
			Language: "ru-RU",
		})
		if !errors.Is(err, domain.ErrSpeechTimeout) {
			t.Fatalf("error = %v, want ErrSpeechTimeout", err)
		}
	})
}

func TestServiceRejectsRequestWhenRecognitionCapacityIsFull(t *testing.T) {
	provider := &blockingProvider{
		started: make(chan struct{}),
		release: make(chan struct{}),
	}
	service := NewService(provider, Policy{
		RecognitionTimeout: time.Second,
		MaxAudioBytes:      1024,
		MaxDuration:        time.Second,
		SupportedLanguages: []string{"ru-RU"},
		MaxConcurrent:      1,
	})
	input := TranscribeInput{
		WAV:      makePCM16WAV(requiredSampleRate, requiredChannels, make([]byte, 100)),
		Language: "ru-RU",
	}
	firstResult := make(chan error, 1)
	go func() {
		_, err := service.Transcribe(context.Background(), input)
		firstResult <- err
	}()
	<-provider.started

	_, err := service.Transcribe(context.Background(), input)
	if !errors.Is(err, domain.ErrSpeechBusy) {
		t.Fatalf("error = %v, want ErrSpeechBusy", err)
	}

	close(provider.release)
	if err := <-firstResult; err != nil {
		t.Fatalf("first transcription error = %v", err)
	}
}

func newTestService(provider speechprovider.Provider) *Service {
	return NewService(provider, Policy{
		RecognitionTimeout: time.Second,
		MaxAudioBytes:      1 << 20,
		MaxDuration:        30 * time.Second,
		SupportedLanguages: []string{"ru-RU", "en-US"},
		MaxConcurrent:      2,
	})
}

func makePCM16WAV(sampleRate uint32, channels uint16, pcm []byte) []byte {
	bitsPerSample := uint16(16)
	blockAlign := channels * bitsPerSample / 8
	byteRate := sampleRate * uint32(blockAlign)
	data := make([]byte, 44+len(pcm))
	copy(data[0:4], "RIFF")
	binary.LittleEndian.PutUint32(data[4:8], uint32(len(data)-8))
	copy(data[8:12], "WAVE")
	copy(data[12:16], "fmt ")
	binary.LittleEndian.PutUint32(data[16:20], 16)
	binary.LittleEndian.PutUint16(data[20:22], linearPCMFormat)
	binary.LittleEndian.PutUint16(data[22:24], channels)
	binary.LittleEndian.PutUint32(data[24:28], sampleRate)
	binary.LittleEndian.PutUint32(data[28:32], byteRate)
	binary.LittleEndian.PutUint16(data[32:34], blockAlign)
	binary.LittleEndian.PutUint16(data[34:36], bitsPerSample)
	copy(data[36:40], "data")
	binary.LittleEndian.PutUint32(data[40:44], uint32(len(pcm)))
	copy(data[44:], pcm)
	return data
}
