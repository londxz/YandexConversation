// Created by Rodion Kholodov.

package security

import (
	"bytes"
	"testing"
)

func TestCredentialManagerIssuesOpaqueTokensAndHashes(t *testing.T) {
	manager, err := NewCredentialManager(bytes.Repeat([]byte{0x42}, 32))
	if err != nil {
		t.Fatalf("NewCredentialManager() error = %v", err)
	}

	accessToken, accessHash, err := manager.NewAccessToken()
	if err != nil {
		t.Fatalf("NewAccessToken() error = %v", err)
	}
	secondToken, secondHash, err := manager.NewAccessToken()
	if err != nil {
		t.Fatalf("second NewAccessToken() error = %v", err)
	}

	if !manager.IsAccessToken(accessToken) {
		t.Fatal("issued access token is not recognized")
	}
	if manager.IsRefreshToken(accessToken) {
		t.Fatal("access token is recognized as refresh token")
	}
	if accessToken == secondToken {
		t.Fatal("two issued access tokens are equal")
	}
	if bytes.Equal(accessHash, secondHash) {
		t.Fatal("two access token hashes are equal")
	}
	if len(accessHash) != 32 {
		t.Fatalf("access hash length = %d, want 32", len(accessHash))
	}
	if !bytes.Equal(accessHash, manager.HashToken(accessToken)) {
		t.Fatal("access token hash is not stable")
	}
}

func TestUUIDGenerationProducesValidUniqueValues(t *testing.T) {
	first, err := NewUUID()
	if err != nil {
		t.Fatalf("NewUUID() error = %v", err)
	}
	second, err := NewUUID()
	if err != nil {
		t.Fatalf("second NewUUID() error = %v", err)
	}

	if !IsUUID(first) || !IsUUID(second) {
		t.Fatalf("generated invalid UUIDs: %q, %q", first, second)
	}
	if first == second {
		t.Fatal("two generated UUIDs are equal")
	}
}
