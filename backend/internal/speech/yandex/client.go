// Created by Rodion Kholodov.

package yandex

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	speechprovider "github.com/londxz/HackatonYandex/backend/internal/speech"
)

const maxResponseBytes = 64 << 10

type Client struct {
	endpoint   *url.URL
	apiKey     string
	httpClient *http.Client
}

type recognitionResponse struct {
	Result       string `json:"result"`
	ErrorCode    string `json:"error_code"`
	ErrorMessage string `json:"error_message"`
}

func NewClient(endpoint *url.URL, apiKey string, httpClient *http.Client) *Client {
	clonedEndpoint := *endpoint
	return &Client{
		endpoint:   &clonedEndpoint,
		apiKey:     apiKey,
		httpClient: httpClient,
	}
}

func (client *Client) Transcribe(
	ctx context.Context,
	input speechprovider.RecognitionRequest,
) (speechprovider.RecognitionResult, error) {
	requestURL := *client.endpoint
	query := requestURL.Query()
	query.Set("topic", "general")
	query.Set("lang", input.Language)
	query.Set("format", "lpcm")
	query.Set("sampleRateHertz", strconv.Itoa(input.SampleRateHertz))
	requestURL.RawQuery = query.Encode()

	request, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		requestURL.String(),
		bytes.NewReader(input.PCM16LittleEndian),
	)
	if err != nil {
		return speechprovider.RecognitionResult{}, fmt.Errorf("create SpeechKit request: %w", err)
	}
	request.Header.Set("Authorization", "Api-Key "+client.apiKey)
	request.Header.Set("Content-Type", "application/octet-stream")
	request.Header.Set("Accept", "application/json")

	response, err := client.httpClient.Do(request)
	if err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return speechprovider.RecognitionResult{}, err
		}
		return speechprovider.RecognitionResult{}, fmt.Errorf("%w: request failed", speechprovider.ErrUnavailable)
	}
	defer response.Body.Close()

	body, err := io.ReadAll(io.LimitReader(response.Body, maxResponseBytes+1))
	if err != nil || len(body) > maxResponseBytes {
		return speechprovider.RecognitionResult{}, fmt.Errorf("%w: invalid response", speechprovider.ErrUnavailable)
	}
	if response.StatusCode != http.StatusOK {
		return speechprovider.RecognitionResult{}, statusError(response.StatusCode)
	}

	var decoded recognitionResponse
	if err := json.Unmarshal(body, &decoded); err != nil {
		return speechprovider.RecognitionResult{}, fmt.Errorf("%w: invalid response", speechprovider.ErrUnavailable)
	}
	if strings.TrimSpace(decoded.ErrorCode) != "" {
		return speechprovider.RecognitionResult{}, fmt.Errorf("%w: provider error", speechprovider.ErrRejected)
	}

	return speechprovider.RecognitionResult{
		Text: strings.TrimSpace(decoded.Result),
	}, nil
}

func statusError(statusCode int) error {
	switch {
	case statusCode == http.StatusUnauthorized || statusCode == http.StatusForbidden:
		return speechprovider.ErrUnauthorized
	case statusCode == http.StatusTooManyRequests || statusCode >= http.StatusInternalServerError:
		return speechprovider.ErrUnavailable
	case statusCode >= http.StatusBadRequest && statusCode < http.StatusInternalServerError:
		return speechprovider.ErrRejected
	default:
		return speechprovider.ErrUnavailable
	}
}
