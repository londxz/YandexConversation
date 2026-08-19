// Created by Rodion Kholodov.

package speech

import (
	"encoding/binary"
	"errors"
	"fmt"
	"time"

	"github.com/londxz/HackatonYandex/backend/internal/domain"
)

const (
	linearPCMFormat       = 1
	requiredChannels      = 1
	requiredSampleRate    = 16000
	requiredBitsPerSample = 16
	requiredBlockAlign    = requiredChannels * requiredBitsPerSample / 8
	requiredByteRate      = requiredSampleRate * requiredBlockAlign
)

type parsedWAV struct {
	pcm      []byte
	duration time.Duration
}

type wavFormat struct {
	audioFormat   uint16
	channels      uint16
	sampleRate    uint32
	byteRate      uint32
	blockAlign    uint16
	bitsPerSample uint16
}

func parseWAV(data []byte, maxAudioBytes int64, maxDuration time.Duration) (parsedWAV, error) {
	if len(data) < 12 || string(data[:4]) != "RIFF" || string(data[8:12]) != "WAVE" {
		return parsedWAV{}, domain.ErrInvalidAudio
	}

	declaredSize := uint64(binary.LittleEndian.Uint32(data[4:8])) + 8
	if declaredSize != uint64(len(data)) {
		return parsedWAV{}, domain.ErrInvalidAudio
	}

	var format *wavFormat
	var pcm []byte
	for offset := 12; offset+8 <= len(data); {
		chunkID := string(data[offset : offset+4])
		chunkSize := uint64(binary.LittleEndian.Uint32(data[offset+4 : offset+8]))
		chunkStart := uint64(offset + 8)
		chunkEnd := chunkStart + chunkSize
		if chunkEnd > uint64(len(data)) {
			return parsedWAV{}, domain.ErrInvalidAudio
		}

		switch chunkID {
		case "fmt ":
			if format != nil || chunkSize < 16 {
				return parsedWAV{}, domain.ErrInvalidAudio
			}
			chunk := data[chunkStart:chunkEnd]
			format = &wavFormat{
				audioFormat:   binary.LittleEndian.Uint16(chunk[0:2]),
				channels:      binary.LittleEndian.Uint16(chunk[2:4]),
				sampleRate:    binary.LittleEndian.Uint32(chunk[4:8]),
				byteRate:      binary.LittleEndian.Uint32(chunk[8:12]),
				blockAlign:    binary.LittleEndian.Uint16(chunk[12:14]),
				bitsPerSample: binary.LittleEndian.Uint16(chunk[14:16]),
			}
		case "data":
			if pcm != nil {
				return parsedWAV{}, domain.ErrInvalidAudio
			}
			if chunkSize > uint64(maxAudioBytes) {
				return parsedWAV{}, domain.ErrAudioTooLarge
			}
			pcm = data[chunkStart:chunkEnd]
		}

		nextOffset := chunkEnd
		if chunkSize%2 != 0 {
			nextOffset++
		}
		if nextOffset > uint64(len(data)) {
			return parsedWAV{}, domain.ErrInvalidAudio
		}
		offset = int(nextOffset)
	}

	if format == nil || len(pcm) == 0 {
		return parsedWAV{}, domain.ErrInvalidAudio
	}
	if err := validateWAVFormat(*format); err != nil {
		return parsedWAV{}, err
	}
	if len(pcm)%requiredBlockAlign != 0 {
		return parsedWAV{}, domain.ErrInvalidAudio
	}

	duration := time.Duration(int64(len(pcm))) * time.Second / requiredByteRate
	if duration > maxDuration {
		return parsedWAV{}, domain.ErrAudioTooLong
	}

	return parsedWAV{pcm: pcm, duration: duration}, nil
}

func validateWAVFormat(format wavFormat) error {
	if format.audioFormat != linearPCMFormat ||
		format.channels != requiredChannels ||
		format.sampleRate != requiredSampleRate ||
		format.bitsPerSample != requiredBitsPerSample ||
		format.blockAlign != requiredBlockAlign ||
		format.byteRate != requiredByteRate {
		return fmt.Errorf("%w: expected PCM16 16kHz mono", domain.ErrInvalidAudio)
	}
	return nil
}

func isWAVError(err error) bool {
	return errors.Is(err, domain.ErrInvalidAudio) ||
		errors.Is(err, domain.ErrAudioTooLarge) ||
		errors.Is(err, domain.ErrAudioTooLong)
}
