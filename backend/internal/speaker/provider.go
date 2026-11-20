// Created by Rodion Kholodov.

package speaker

import (
	"context"
	"errors"
)

var (
	ErrUnavailable = errors.New("speaker embedding provider is unavailable")
	ErrRejected    = errors.New("speaker embedding provider rejected audio")
)

type EmbeddingRequest struct {
	WAV               []byte
	PCM16LittleEndian []byte
	SampleRateHertz   int
	Channels          int
}

type EmbeddingResult struct {
	Vector []float32
}

type Provider interface {
	Embed(context.Context, EmbeddingRequest) (EmbeddingResult, error)
}

type UnavailableProvider struct{}

func (UnavailableProvider) Embed(
	context.Context,
	EmbeddingRequest,
) (EmbeddingResult, error) {
	return EmbeddingResult{}, ErrUnavailable
}
