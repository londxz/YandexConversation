// Created by Rodion Kholodov.

package whisper

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/url"
	"strings"

	speechprovider "github.com/londxz/HackatonYandex/backend/internal/speech"
)

const maxResponseBytes = 256 << 10

type Client struct {
	endpoint   *url.URL
	httpClient *http.Client
}

func NewClient(endpoint string, httpClient *http.Client) (*Client, error) {
	parsedEndpoint, err := url.ParseRequestURI(strings.TrimSpace(endpoint))
	if err != nil || parsedEndpoint.Host == "" || (parsedEndpoint.Scheme != "http" && parsedEndpoint.Scheme != "https") {
		return nil, errors.New("whisper endpoint must be an absolute HTTP or HTTPS URL")
	}
	if httpClient == nil {
		return nil, errors.New("whisper HTTP client is required")
	}
	return &Client{endpoint: parsedEndpoint, httpClient: httpClient}, nil
}

func (client *Client) Transcribe(
	ctx context.Context,
	request speechprovider.RecognitionRequest,
) (speechprovider.RecognitionResult, error) {
	if len(request.WAV) == 0 {
		return speechprovider.RecognitionResult{}, speechprovider.ErrRejected
	}

	body := bytes.NewBuffer(nil)
	writer := multipart.NewWriter(body)
	filePart, err := writer.CreateFormFile("file", "audio.wav")
	if err != nil {
		return speechprovider.RecognitionResult{}, fmt.Errorf("create audio form field: %w", err)
	}
	if _, err := filePart.Write(request.WAV); err != nil {
		return speechprovider.RecognitionResult{}, fmt.Errorf("write audio form field: %w", err)
	}
	fields := map[string]string{
		"language":        whisperLanguage(request.Language),
		"response_format": "json",
		"temperature":     "0.0",
		"temperature_inc": "0.2",
	}
	for name, value := range fields {
		if err := writer.WriteField(name, value); err != nil {
			return speechprovider.RecognitionResult{}, fmt.Errorf("write %s form field: %w", name, err)
		}
	}
	if err := writer.Close(); err != nil {
		return speechprovider.RecognitionResult{}, fmt.Errorf("close speech form: %w", err)
	}

	httpRequest, err := http.NewRequestWithContext(ctx, http.MethodPost, client.endpoint.String(), body)
	if err != nil {
		return speechprovider.RecognitionResult{}, fmt.Errorf("create whisper request: %w", err)
	}
	httpRequest.Header.Set("Content-Type", writer.FormDataContentType())
	httpRequest.Header.Set("Accept", "application/json")

	response, err := client.httpClient.Do(httpRequest)
	if err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return speechprovider.RecognitionResult{}, err
		}
		return speechprovider.RecognitionResult{}, fmt.Errorf("%w: whisper request failed", speechprovider.ErrUnavailable)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		return speechprovider.RecognitionResult{}, providerError(response.StatusCode)
	}

	limitedBody := io.LimitReader(response.Body, maxResponseBytes+1)
	responseData, err := io.ReadAll(limitedBody)
	if err != nil {
		return speechprovider.RecognitionResult{}, fmt.Errorf("%w: read whisper response", speechprovider.ErrUnavailable)
	}
	if len(responseData) > maxResponseBytes {
		return speechprovider.RecognitionResult{}, fmt.Errorf("%w: whisper response is too large", speechprovider.ErrUnavailable)
	}

	var payload struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal(responseData, &payload); err != nil {
		return speechprovider.RecognitionResult{}, fmt.Errorf("%w: decode whisper response", speechprovider.ErrUnavailable)
	}
	return speechprovider.RecognitionResult{Text: strings.TrimSpace(payload.Text)}, nil
}

func whisperLanguage(language string) string {
	baseLanguage, _, _ := strings.Cut(strings.TrimSpace(language), "-")
	return strings.ToLower(baseLanguage)
}

func providerError(statusCode int) error {
	switch {
	case statusCode == http.StatusUnauthorized || statusCode == http.StatusForbidden:
		return speechprovider.ErrUnauthorized
	case statusCode == http.StatusBadRequest,
		statusCode == http.StatusRequestEntityTooLarge,
		statusCode == http.StatusUnsupportedMediaType,
		statusCode == http.StatusUnprocessableEntity:
		return speechprovider.ErrRejected
	default:
		return speechprovider.ErrUnavailable
	}
}
