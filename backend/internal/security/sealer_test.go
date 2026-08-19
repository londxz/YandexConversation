// Created by Rodion Kholodov.

package security

import (
	"bytes"
	"testing"
)

func TestSealerRoundTripRequiresMatchingAssociatedData(t *testing.T) {
	sealer, err := NewSealer(bytes.Repeat([]byte{0x24}, 32))
	if err != nil {
		t.Fatalf("NewSealer() error = %v", err)
	}

	plaintext := []byte("sensitive session response")
	associatedData := []byte("devices.register\x00idempotency-key")
	ciphertext, err := sealer.Seal(plaintext, associatedData)
	if err != nil {
		t.Fatalf("Seal() error = %v", err)
	}
	if bytes.Contains(ciphertext, plaintext) {
		t.Fatal("ciphertext contains plaintext")
	}

	opened, err := sealer.Open(ciphertext, associatedData)
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	if !bytes.Equal(opened, plaintext) {
		t.Fatalf("opened payload = %q, want %q", opened, plaintext)
	}
	if _, err := sealer.Open(ciphertext, []byte("another-key")); err == nil {
		t.Fatal("Open() with different associated data error = nil")
	}
}
