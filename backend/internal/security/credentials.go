// Created by Rodion Kholodov.

package security

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
)

const (
	accessTokenPrefix  = "rv_access_"
	refreshTokenPrefix = "rv_refresh_"
	tokenRandomBytes   = 32
)

type CredentialManager struct {
	pepper []byte
}

func NewCredentialManager(pepper []byte) (*CredentialManager, error) {
	if len(pepper) != 32 {
		return nil, errors.New("token pepper must contain exactly 32 bytes")
	}

	return &CredentialManager{pepper: append([]byte(nil), pepper...)}, nil
}

func (manager *CredentialManager) NewAccessToken() (string, []byte, error) {
	return manager.newToken(accessTokenPrefix)
}

func (manager *CredentialManager) NewRefreshToken() (string, []byte, error) {
	return manager.newToken(refreshTokenPrefix)
}

func (manager *CredentialManager) HashToken(token string) []byte {
	mac := hmac.New(sha256.New, manager.pepper)
	_, _ = mac.Write([]byte(token))
	return mac.Sum(nil)
}

func (manager *CredentialManager) IsAccessToken(token string) bool {
	return validToken(token, accessTokenPrefix)
}

func (manager *CredentialManager) IsRefreshToken(token string) bool {
	return validToken(token, refreshTokenPrefix)
}

func (manager *CredentialManager) newToken(prefix string) (string, []byte, error) {
	random := make([]byte, tokenRandomBytes)
	if _, err := rand.Read(random); err != nil {
		return "", nil, fmt.Errorf("generate token: %w", err)
	}

	token := prefix + base64.RawURLEncoding.EncodeToString(random)
	return token, manager.HashToken(token), nil
}

func validToken(token string, prefix string) bool {
	if !strings.HasPrefix(token, prefix) {
		return false
	}
	encoded := strings.TrimPrefix(token, prefix)
	decoded, err := base64.RawURLEncoding.DecodeString(encoded)
	return err == nil && len(decoded) == tokenRandomBytes
}

func NewUUID() (string, error) {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return "", fmt.Errorf("generate UUID: %w", err)
	}

	value[6] = (value[6] & 0x0f) | 0x40
	value[8] = (value[8] & 0x3f) | 0x80
	encoded := hex.EncodeToString(value)
	return encoded[0:8] + "-" + encoded[8:12] + "-" + encoded[12:16] + "-" + encoded[16:20] + "-" + encoded[20:32], nil
}

func IsUUID(value string) bool {
	if len(value) != 36 || value[8] != '-' || value[13] != '-' || value[18] != '-' || value[23] != '-' {
		return false
	}

	compact := strings.ReplaceAll(value, "-", "")
	decoded, err := hex.DecodeString(compact)
	return err == nil && len(decoded) == 16
}
