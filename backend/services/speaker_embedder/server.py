# Created by Rodion Kholodov.

import io
import json
import logging
import os
import threading
import wave
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from time import monotonic

import numpy as np
import sherpa_onnx


SAMPLE_RATE = 16_000
CHANNELS = 1
SAMPLE_WIDTH = 2


class InvalidAudio(Exception):
    pass


class EmbeddingEngine:
    def __init__(self, model_path: str, num_threads: int) -> None:
        config = sherpa_onnx.SpeakerEmbeddingExtractorConfig(
            model=model_path,
            num_threads=num_threads,
            debug=False,
            provider="cpu",
        )
        if not config.validate():
            raise RuntimeError("speaker embedding configuration is invalid")
        self._extractor = sherpa_onnx.SpeakerEmbeddingExtractor(config)
        self._lock = threading.Lock()

    def embedding(self, payload: bytes) -> list[float]:
        samples = self._decode_pcm16_wav(payload)
        stream = self._extractor.create_stream()
        stream.accept_waveform(sample_rate=SAMPLE_RATE, waveform=samples)
        stream.input_finished()
        if not self._extractor.is_ready(stream):
            raise InvalidAudio("audio is too short for a reliable embedding")

        with self._lock:
            vector = np.asarray(self._extractor.compute(stream), dtype=np.float32)
        if vector.ndim != 1 or vector.size < 32 or not np.all(np.isfinite(vector)):
            raise RuntimeError("speaker embedding result is invalid")
        return vector.tolist()

    @staticmethod
    def _decode_pcm16_wav(payload: bytes) -> np.ndarray:
        try:
            with wave.open(io.BytesIO(payload), "rb") as wav_file:
                if (
                    wav_file.getnchannels() != CHANNELS
                    or wav_file.getsampwidth() != SAMPLE_WIDTH
                    or wav_file.getframerate() != SAMPLE_RATE
                    or wav_file.getcomptype() != "NONE"
                ):
                    raise InvalidAudio("expected PCM16 16kHz mono WAV")
                frames = wav_file.readframes(wav_file.getnframes())
        except (EOFError, wave.Error) as error:
            raise InvalidAudio("invalid WAV container") from error

        if not frames or len(frames) % SAMPLE_WIDTH != 0:
            raise InvalidAudio("audio payload is empty or malformed")
        samples = np.frombuffer(frames, dtype="<i2").astype(np.float32)
        return np.ascontiguousarray(samples / 32768.0)


class EmbeddingHTTPServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(
        self,
        address: tuple[str, int],
        engine: EmbeddingEngine,
        max_audio_bytes: int,
    ) -> None:
        super().__init__(address, EmbeddingRequestHandler)
        self.engine = engine
        self.max_audio_bytes = max_audio_bytes


class EmbeddingRequestHandler(BaseHTTPRequestHandler):
    server: EmbeddingHTTPServer
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:
        if self.path != "/healthz":
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return
        self._send_json(HTTPStatus.OK, {"status": "ok"})

    def do_POST(self) -> None:
        started_at = monotonic()
        status = HTTPStatus.INTERNAL_SERVER_ERROR
        try:
            if self.path != "/v1/embedding":
                status = HTTPStatus.NOT_FOUND
                self._send_json(status, {"error": "not_found"})
                return
            if self.headers.get_content_type() != "audio/wav":
                status = HTTPStatus.UNSUPPORTED_MEDIA_TYPE
                self._send_json(status, {"error": "unsupported_media_type"})
                return

            content_length = self._content_length()
            if content_length > self.server.max_audio_bytes:
                status = HTTPStatus.REQUEST_ENTITY_TOO_LARGE
                self._send_json(status, {"error": "audio_too_large"})
                return
            payload = self.rfile.read(content_length)
            if len(payload) != content_length:
                raise InvalidAudio("request body is truncated")

            embedding = self.server.engine.embedding(payload)
            status = HTTPStatus.OK
            self._send_json(status, {"embedding": embedding})
        except InvalidAudio:
            status = HTTPStatus.UNPROCESSABLE_ENTITY
            self._send_json(status, {"error": "invalid_audio"})
        except Exception:
            logging.exception("speaker embedding request failed")
            status = HTTPStatus.INTERNAL_SERVER_ERROR
            self._send_json(status, {"error": "embedding_unavailable"})
        finally:
            logging.info(
                "embedding request completed status=%d duration_ms=%d",
                status,
                int((monotonic() - started_at) * 1000),
            )

    def _content_length(self) -> int:
        raw_value = self.headers.get("Content-Length")
        if raw_value is None:
            raise InvalidAudio("Content-Length is required")
        try:
            value = int(raw_value)
        except ValueError as error:
            raise InvalidAudio("Content-Length is invalid") from error
        if value <= 0:
            raise InvalidAudio("request body is empty")
        return value

    def _send_json(self, status: HTTPStatus, payload: dict) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format_string: str, *args: object) -> None:
        logging.info("http request " + format_string, *args)


def positive_int(name: str, fallback: int) -> int:
    raw_value = os.getenv(name, str(fallback)).strip()
    try:
        value = int(raw_value)
    except ValueError as error:
        raise RuntimeError(f"{name} must be a positive integer") from error
    if value <= 0:
        raise RuntimeError(f"{name} must be a positive integer")
    return value


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    model_path = os.getenv(
        "SPEAKER_EMBEDDING_MODEL",
        "/opt/speaker-embedder/models/campplus-en-voxceleb.onnx",
    )
    port = positive_int("PORT", 8090)
    num_threads = positive_int("SPEAKER_EMBEDDING_THREADS", 2)
    max_audio_bytes = positive_int("SPEAKER_EMBEDDING_MAX_AUDIO_BYTES", 1 << 20)
    engine = EmbeddingEngine(model_path=model_path, num_threads=num_threads)
    server = EmbeddingHTTPServer(("0.0.0.0", port), engine, max_audio_bytes)
    logging.info("speaker embedding service started port=%d", port)
    server.serve_forever()


if __name__ == "__main__":
    main()
