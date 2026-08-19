// Created by Rodion Kholodov.

package speech

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/londxz/HackatonYandex/backend/internal/domain"
	speechprovider "github.com/londxz/HackatonYandex/backend/internal/speech"
)

type Service struct {
	provider           speechprovider.Provider
	recognitionTimeout time.Duration
	maxAudioBytes      int64
	maxDuration        time.Duration
	supportedLanguages map[string]struct{}
	requestSlots       chan struct{}
}

type TranscribeInput struct {
	WAV      []byte
	Language string
}

type Policy struct {
	RecognitionTimeout time.Duration
	MaxAudioBytes      int64
	MaxDuration        time.Duration
	SupportedLanguages []string
	MaxConcurrent      int
}

func NewService(provider speechprovider.Provider, policy Policy) *Service {
	supportedLanguages := make(map[string]struct{}, len(policy.SupportedLanguages))
	for _, language := range policy.SupportedLanguages {
		supportedLanguages[language] = struct{}{}
	}
	return &Service{
		provider:           provider,
		recognitionTimeout: policy.RecognitionTimeout,
		maxAudioBytes:      policy.MaxAudioBytes,
		maxDuration:        policy.MaxDuration,
		supportedLanguages: supportedLanguages,
		requestSlots:       make(chan struct{}, policy.MaxConcurrent),
	}
}

func (service *Service) Transcribe(
	ctx context.Context,
	input TranscribeInput,
) (domain.SpeechTranscript, error) {
	language := strings.TrimSpace(input.Language)
	if _, supported := service.supportedLanguages[language]; !supported {
		return domain.SpeechTranscript{}, domain.ErrUnsupportedLanguage
	}

	audio, err := parseWAV(input.WAV, service.maxAudioBytes, service.maxDuration)
	if err != nil {
		if isWAVError(err) {
			return domain.SpeechTranscript{}, err
		}
		return domain.SpeechTranscript{}, fmt.Errorf("parse WAV: %w", err)
	}
	select {
	case service.requestSlots <- struct{}{}:
		defer func() { <-service.requestSlots }()
	default:
		return domain.SpeechTranscript{}, domain.ErrSpeechBusy
	}

	recognitionContext, cancel := context.WithTimeout(ctx, service.recognitionTimeout)
	defer cancel()
	result, err := service.provider.Transcribe(
		recognitionContext,
		speechprovider.RecognitionRequest{
			PCM16LittleEndian: audio.pcm,
			Language:          language,
			SampleRateHertz:   requiredSampleRate,
			Channels:          requiredChannels,
		},
	)
	if err != nil {
		switch {
		case errors.Is(err, context.DeadlineExceeded), errors.Is(recognitionContext.Err(), context.DeadlineExceeded):
			return domain.SpeechTranscript{}, domain.ErrSpeechTimeout
		case errors.Is(err, speechprovider.ErrRejected):
			return domain.SpeechTranscript{}, fmt.Errorf("%w: %v", domain.ErrSpeechProvider, err)
		case errors.Is(err, speechprovider.ErrUnavailable), errors.Is(err, speechprovider.ErrUnauthorized):
			return domain.SpeechTranscript{}, fmt.Errorf("%w: %v", domain.ErrSpeechUnavailable, err)
		default:
			return domain.SpeechTranscript{}, fmt.Errorf("%w: %v", domain.ErrSpeechUnavailable, err)
		}
	}

	return domain.SpeechTranscript{
		Text:       strings.TrimSpace(result.Text),
		Language:   language,
		Duration:   audio.duration,
		Confidence: result.Confidence,
	}, nil
}
