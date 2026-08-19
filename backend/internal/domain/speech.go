// Created by Rodion Kholodov.

package domain

import (
	"errors"
	"time"
)

var (
	ErrInvalidAudio        = errors.New("audio is invalid")
	ErrAudioTooLarge       = errors.New("audio is too large")
	ErrAudioTooLong        = errors.New("audio is too long")
	ErrUnsupportedLanguage = errors.New("speech language is unsupported")
	ErrSpeechUnavailable   = errors.New("speech recognition is unavailable")
	ErrSpeechProvider      = errors.New("speech provider rejected the request")
	ErrSpeechTimeout       = errors.New("speech recognition timed out")
	ErrSpeechBusy          = errors.New("speech recognition capacity is exhausted")
)

type SpeechTranscript struct {
	Text       string
	Language   string
	Duration   time.Duration
	Confidence *float64
}
