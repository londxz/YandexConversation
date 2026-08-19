// Created by Rodion Kholodov.

package security

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"errors"
	"fmt"
	"io"
)

type Sealer struct {
	aead cipher.AEAD
}

func NewSealer(key []byte) (*Sealer, error) {
	if len(key) != 32 {
		return nil, errors.New("encryption key must contain exactly 32 bytes")
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("create AES cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("create GCM: %w", err)
	}
	return &Sealer{aead: aead}, nil
}

func (sealer *Sealer) Seal(plaintext []byte, associatedData []byte) ([]byte, error) {
	nonce := make([]byte, sealer.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, fmt.Errorf("generate encryption nonce: %w", err)
	}

	return sealer.aead.Seal(nonce, nonce, plaintext, associatedData), nil
}

func (sealer *Sealer) Open(ciphertext []byte, associatedData []byte) ([]byte, error) {
	nonceSize := sealer.aead.NonceSize()
	if len(ciphertext) < nonceSize {
		return nil, errors.New("encrypted payload is too short")
	}

	nonce := ciphertext[:nonceSize]
	plaintext, err := sealer.aead.Open(nil, nonce, ciphertext[nonceSize:], associatedData)
	if err != nil {
		return nil, fmt.Errorf("decrypt payload: %w", err)
	}
	return plaintext, nil
}
