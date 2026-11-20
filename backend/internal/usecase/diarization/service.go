// Created by Rodion Kholodov.

package diarization

import (
	"context"
	"errors"
	"fmt"
	"math"
	"sync"
	"time"

	"github.com/londxz/HackatonYandex/backend/internal/speaker"
)

var (
	ErrUnavailable       = errors.New("speaker diarization is unavailable")
	ErrInsufficientAudio = errors.New("audio is too short for speaker diarization")
)

const pcmBytesPerSecond = 16000 * 2

type Policy struct {
	EmbeddingTimeout    time.Duration
	MinimumAudio        time.Duration
	SimilarityThreshold float64
	MaximumSpeakers     int
	MaxConcurrent       int
}

type Identity struct {
	ID         string
	Label      string
	Confidence *float64
}

type Service struct {
	provider     speaker.Provider
	policy       Policy
	requestSlots chan struct{}
}

type Session struct {
	mu       sync.Mutex
	policy   Policy
	clusters []speakerCluster
}

type speakerCluster struct {
	centroid []float64
	count    int
}

func NewService(provider speaker.Provider, policy Policy) *Service {
	return &Service{
		provider:     provider,
		policy:       policy,
		requestSlots: make(chan struct{}, policy.MaxConcurrent),
	}
}

func (service *Service) NewSession() *Session {
	return &Session{policy: service.policy}
}

func (service *Service) Embedding(
	ctx context.Context,
	wav []byte,
	pcm []byte,
) ([]float32, error) {
	if len(pcm) < durationBytes(service.policy.MinimumAudio) {
		return nil, ErrInsufficientAudio
	}
	select {
	case service.requestSlots <- struct{}{}:
		defer func() { <-service.requestSlots }()
	default:
		return nil, ErrUnavailable
	}

	embeddingContext, cancel := context.WithTimeout(ctx, service.policy.EmbeddingTimeout)
	defer cancel()
	result, err := service.provider.Embed(embeddingContext, speaker.EmbeddingRequest{
		WAV:               wav,
		PCM16LittleEndian: pcm,
		SampleRateHertz:   16000,
		Channels:          1,
	})
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrUnavailable, err)
	}
	return result.Vector, nil
}

func (session *Session) Assign(embedding []float32) (Identity, error) {
	normalized, ok := normalize(embedding)
	if !ok {
		return Identity{}, ErrUnavailable
	}

	session.mu.Lock()
	defer session.mu.Unlock()

	bestIndex := -1
	bestSimilarity := -1.0
	for index, cluster := range session.clusters {
		if len(cluster.centroid) != len(normalized) {
			continue
		}
		similarity := dot(cluster.centroid, normalized)
		if similarity > bestSimilarity {
			bestIndex = index
			bestSimilarity = similarity
		}
	}

	if bestIndex < 0 || bestSimilarity < session.policy.SimilarityThreshold {
		if len(session.clusters) >= session.policy.MaximumSpeakers {
			return Identity{ID: "speaker_unknown", Label: "Говорящий"}, nil
		}
		session.clusters = append(session.clusters, speakerCluster{
			centroid: normalized,
			count:    1,
		})
		index := len(session.clusters) - 1
		return identity(index, nil), nil
	}

	cluster := &session.clusters[bestIndex]
	cluster.count++
	weight := 1 / float64(min(cluster.count, 10))
	for index := range cluster.centroid {
		cluster.centroid[index] = cluster.centroid[index]*(1-weight) + normalized[index]*weight
	}
	cluster.centroid = normalizeFloat64(cluster.centroid)
	confidence := max(0, min(1, bestSimilarity))
	return identity(bestIndex, &confidence), nil
}

func identity(index int, confidence *float64) Identity {
	ordinal := index + 1
	return Identity{
		ID:         fmt.Sprintf("speaker_%d", ordinal),
		Label:      fmt.Sprintf("Говорящий %d", ordinal),
		Confidence: confidence,
	}
}

func normalize(vector []float32) ([]float64, bool) {
	if len(vector) == 0 {
		return nil, false
	}
	values := make([]float64, len(vector))
	var magnitudeSquared float64
	for index, value := range vector {
		converted := float64(value)
		if math.IsNaN(converted) || math.IsInf(converted, 0) {
			return nil, false
		}
		values[index] = converted
		magnitudeSquared += converted * converted
	}
	if magnitudeSquared <= 0 {
		return nil, false
	}
	magnitude := math.Sqrt(magnitudeSquared)
	for index := range values {
		values[index] /= magnitude
	}
	return values, true
}

func normalizeFloat64(vector []float64) []float64 {
	var magnitudeSquared float64
	for _, value := range vector {
		magnitudeSquared += value * value
	}
	if magnitudeSquared <= 0 {
		return vector
	}
	magnitude := math.Sqrt(magnitudeSquared)
	for index := range vector {
		vector[index] /= magnitude
	}
	return vector
}

func dot(left []float64, right []float64) float64 {
	var result float64
	for index := range left {
		result += left[index] * right[index]
	}
	return result
}

func durationBytes(duration time.Duration) int {
	return int(duration * pcmBytesPerSecond / time.Second)
}
