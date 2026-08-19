// Created by Rodion Kholodov.

package speech

import (
	"context"
	"errors"
)

var (
	ErrUnavailable  = errors.New("speech provider is unavailable")
	ErrUnauthorized = errors.New("speech provider credentials are invalid")
	ErrRejected     = errors.New("speech provider rejected audio")
)

type RecognitionRequest struct {
	PCM16LittleEndian []byte
	Language          string
	SampleRateHertz   int
	Channels          int
}

type RecognitionResult struct {
	Text       string
	Confidence *float64
}

type Provider interface {
	Transcribe(context.Context, RecognitionRequest) (RecognitionResult, error)
}

type UnavailableProvider struct{}

func (UnavailableProvider) Transcribe(
	context.Context,
	RecognitionRequest,
) (RecognitionResult, error) {
	return RecognitionResult{}, ErrUnavailable
}
