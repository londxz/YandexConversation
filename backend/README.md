# Razgovor Backend

Production Go backend for the Razgovor accessibility application.

## Local start

```bash
docker compose up --build -d
curl -i http://localhost:8080/v1/health
```

The first build compiles the pinned `whisper.cpp` release and downloads the
multilingual `base` model. The local stack then starts PostgreSQL, migrations,
the non-public Whisper sidecar, and the Go API without any cloud credentials.

Compose exposes PostgreSQL on `localhost:5433` by default to avoid colliding
with a locally installed PostgreSQL. Override `POSTGRES_PORT` or `API_PORT`
when needed.

Expected response:

```json
{
  "status": "ok",
  "version": "local",
  "time": "2026-08-19T16:00:00Z"
}
```

## Test from the iOS app

Start the local stack and run the Debug app in iOS Simulator. Debug builds use
`http://127.0.0.1:8080` by default, while staging and production keep their HTTPS
URLs. `RAZGOVOR_API_BASE_URL` remains available as a Run-scheme override for a
physical device or another environment. The app creates its anonymous device
session lazily on the first backend request.

Verify that the app registered exactly one device:

```bash
docker compose exec -T postgres \
  psql -U razgovor -d razgovor -tAc 'SELECT count(*) FROM devices;'
```

Relaunching the app must not increase the count: the installation session is
restored from Keychain instead of being registered again.

Probe endpoints:

- `GET /livez` checks whether the API process is alive.
- `GET /readyz` checks whether PostgreSQL is reachable.
- `GET /v1/health` is the public versioned health contract.

Device session endpoints:

- `POST /v1/devices/register` creates an anonymous installation session.
- `POST /v1/devices/refresh` atomically rotates both opaque tokens.
- `DELETE /v1/devices/{device_id}` permanently deletes the authenticated device and its server data.

Speech endpoint:

- `POST /v1/speech/transcribe` accepts authenticated `multipart/form-data`
  containing `file` (PCM16, 16 kHz, mono WAV), `language`, and an optional
  `conversation_id` UUID.

The synchronous endpoint accepts at most 1 MiB of PCM data and 30 seconds of
audio. Raw audio is kept only in request memory, is not persisted, and is never
written to logs.

Each API instance also bounds concurrent recognition calls; excess requests
receive `429 speech_busy` with `Retry-After: 1`.

The default flow is backend-first: iOS sends the completed push-to-talk WAV to
the authenticated Go endpoint, which validates it and calls the private
`whisper.cpp` sidecar. If the backend is unavailable, iOS automatically retries
the same recording through Apple Speech. Privacy mode bypasses the backend and
requires on-device Apple recognition. No cloud speech key or metered STT API is
required. `SPEECH_PROVIDER=disabled` remains available for deployments that
want the endpoint to return `503 speech_unavailable` and rely on the iOS fallback.

Registration and refresh require a unique `Idempotency-Key` containing 16 to
100 visible ASCII characters. Protected routes use
`Authorization: Bearer <access_token>`. Clients must keep access and refresh
tokens in the iOS Keychain.

Stop local containers:

```bash
docker compose down
```

## Run without Docker

Start PostgreSQL, apply migrations, and provide configuration:

```bash
cp .env.example .env
set -a
source .env
export TOKEN_PEPPER_BASE64="$(openssl rand -base64 32)"
export IDEMPOTENCY_ENCRYPTION_KEY_BASE64="$(openssl rand -base64 32)"
set +a
go run ./cmd/api
```

The application does not read `.env` automatically. Production configuration must come from the deployment environment or secret manager.

`TOKEN_PEPPER_BASE64` and `IDEMPOTENCY_ENCRYPTION_KEY_BASE64` are independent
32-byte secrets. Rotating them requires a deployment migration plan: changing
the pepper invalidates active sessions, while changing the encryption key
invalidates unexpired idempotency replays.

## Validation

```bash
make check
```

This runs formatting, `go vet`, race-enabled tests, and a full build.

Run PostgreSQL integration tests against the Compose database:

```bash
TEST_DATABASE_URL='postgres://razgovor:local-development-password@localhost:5433/razgovor?sslmode=disable' \
  make test-integration
```

## Privacy

Never add raw audio, transcript text, authorization tokens, or request bodies to logs. Request logs contain only metadata such as method, path, status, duration, and request ID.

Opaque tokens are never stored directly in PostgreSQL. Token lookups use
HMAC-SHA-256 hashes, and idempotent responses containing credentials are
encrypted with AES-256-GCM and removed when their owning device is deleted.
