// Created by Rodion Kholodov.

package diarization

import (
	"context"
	"testing"
	"time"

	"github.com/londxz/HackatonYandex/backend/internal/speaker"
)

type embeddingProviderStub struct {
	vectors [][]float32
	calls   int
}

func (stub *embeddingProviderStub) Embed(
	context.Context,
	speaker.EmbeddingRequest,
) (speaker.EmbeddingResult, error) {
	vector := stub.vectors[stub.calls]
	stub.calls++
	return speaker.EmbeddingResult{Vector: vector}, nil
}

func TestSessionKeepsStableSpeakerIdentity(t *testing.T) {
	provider := &embeddingProviderStub{vectors: [][]float32{
		{1, 0, 0},
		{0.99, 0.04, 0},
		{0, 1, 0},
		{0.98, 0.02, 0},
	}}
	service := newTestService(provider)
	session := service.NewSession()

	first := identifyForTest(t, service, session)
	second := identifyForTest(t, service, session)
	third := identifyForTest(t, service, session)
	fourth := identifyForTest(t, service, session)

	if first.ID != "speaker_1" || second.ID != "speaker_1" || fourth.ID != "speaker_1" {
		t.Fatalf("same voice identities = %q, %q, %q", first.ID, second.ID, fourth.ID)
	}
	if third.ID != "speaker_2" || third.Label != "Говорящий 2" {
		t.Fatalf("different voice identity = %#v", third)
	}
	if second.Confidence == nil || *second.Confidence < 0.9 {
		t.Fatalf("same voice confidence = %v", second.Confidence)
	}
}

func TestSessionUsesUnknownWhenSpeakerLimitIsReached(t *testing.T) {
	provider := &embeddingProviderStub{vectors: [][]float32{{1, 0}, {0, 1}}}
	service := NewService(provider, Policy{
		EmbeddingTimeout:    time.Second,
		MinimumAudio:        time.Millisecond,
		SimilarityThreshold: 0.75,
		MaximumSpeakers:     1,
		MaxConcurrent:       1,
	})
	session := service.NewSession()

	_ = identifyForTest(t, service, session)
	unknown := identifyForTest(t, service, session)

	if unknown.ID != "speaker_unknown" || unknown.Label != "Говорящий" {
		t.Fatalf("identity = %#v, want unknown", unknown)
	}
}

func TestServiceRejectsAudioTooShortForReliableEmbedding(t *testing.T) {
	provider := &embeddingProviderStub{vectors: [][]float32{{1, 0}}}
	service := newTestService(provider)

	_, err := service.Embedding(
		context.Background(),
		[]byte("wav"),
		make([]byte, 100),
	)
	if err != ErrInsufficientAudio {
		t.Fatalf("error = %v, want ErrInsufficientAudio", err)
	}
	if provider.calls != 0 {
		t.Fatalf("provider calls = %d, want 0", provider.calls)
	}
}

func identifyForTest(t *testing.T, service *Service, session *Session) Identity {
	t.Helper()
	embedding, err := service.Embedding(
		context.Background(),
		[]byte("wav"),
		make([]byte, 3200),
	)
	if err != nil {
		t.Fatalf("Embedding() error = %v", err)
	}
	identity, err := session.Assign(embedding)
	if err != nil {
		t.Fatalf("Assign() error = %v", err)
	}
	return identity
}

func newTestService(provider speaker.Provider) *Service {
	return NewService(provider, Policy{
		EmbeddingTimeout:    time.Second,
		MinimumAudio:        50 * time.Millisecond,
		SimilarityThreshold: 0.75,
		MaximumSpeakers:     8,
		MaxConcurrent:       2,
	})
}
