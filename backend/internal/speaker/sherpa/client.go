// Created by Rodion Kholodov.

package sherpa

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strings"

	"github.com/londxz/HackatonYandex/backend/internal/speaker"
)

const (
	maxResponseBytes = 128 << 10
	minEmbeddingSize = 32
	maxEmbeddingSize = 4096
)

type Client struct {
	endpoint   *url.URL
	httpClient *http.Client
}

func NewClient(endpoint string, httpClient *http.Client) (*Client, error) {
	parsedEndpoint, err := url.ParseRequestURI(strings.TrimSpace(endpoint))
	if err != nil || parsedEndpoint.Host == "" || (parsedEndpoint.Scheme != "http" && parsedEndpoint.Scheme != "https") {
		return nil, errors.New("speaker embedding endpoint must be an absolute HTTP or HTTPS URL")
	}
	if httpClient == nil {
		return nil, errors.New("speaker embedding HTTP client is required")
	}
	return &Client{endpoint: parsedEndpoint, httpClient: httpClient}, nil
}

func (client *Client) Embed(
	ctx context.Context,
	request speaker.EmbeddingRequest,
) (speaker.EmbeddingResult, error) {
	if len(request.WAV) == 0 {
		return speaker.EmbeddingResult{}, speaker.ErrRejected
	}

	httpRequest, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		client.endpoint.String(),
		bytes.NewReader(request.WAV),
	)
	if err != nil {
		return speaker.EmbeddingResult{}, fmt.Errorf("create speaker embedding request: %w", err)
	}
	httpRequest.Header.Set("Content-Type", "audio/wav")
	httpRequest.Header.Set("Accept", "application/json")

	response, err := client.httpClient.Do(httpRequest)
	if err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return speaker.EmbeddingResult{}, err
		}
		return speaker.EmbeddingResult{}, fmt.Errorf("%w: embedding request failed", speaker.ErrUnavailable)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		if response.StatusCode == http.StatusBadRequest ||
			response.StatusCode == http.StatusRequestEntityTooLarge ||
			response.StatusCode == http.StatusUnsupportedMediaType ||
			response.StatusCode == http.StatusUnprocessableEntity {
			return speaker.EmbeddingResult{}, speaker.ErrRejected
		}
		return speaker.EmbeddingResult{}, speaker.ErrUnavailable
	}

	limitedBody := io.LimitReader(response.Body, maxResponseBytes+1)
	responseData, err := io.ReadAll(limitedBody)
	if err != nil {
		return speaker.EmbeddingResult{}, fmt.Errorf("%w: read embedding response", speaker.ErrUnavailable)
	}
	if len(responseData) > maxResponseBytes {
		return speaker.EmbeddingResult{}, fmt.Errorf("%w: embedding response is too large", speaker.ErrUnavailable)
	}

	var payload struct {
		Embedding []float32 `json:"embedding"`
	}
	if err := json.Unmarshal(responseData, &payload); err != nil {
		return speaker.EmbeddingResult{}, fmt.Errorf("%w: decode embedding response", speaker.ErrUnavailable)
	}
	if len(payload.Embedding) < minEmbeddingSize || len(payload.Embedding) > maxEmbeddingSize {
		return speaker.EmbeddingResult{}, fmt.Errorf("%w: embedding size is invalid", speaker.ErrUnavailable)
	}
	for _, value := range payload.Embedding {
		if math.IsNaN(float64(value)) || math.IsInf(float64(value), 0) {
			return speaker.EmbeddingResult{}, fmt.Errorf("%w: embedding contains a non-finite value", speaker.ErrUnavailable)
		}
	}
	return speaker.EmbeddingResult{Vector: payload.Embedding}, nil
}
