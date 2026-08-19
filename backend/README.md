# Razgovor Backend

Production Go backend for the Razgovor accessibility application.

## Local start

```bash
docker compose up --build -d
curl -i http://localhost:8080/v1/health
```

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

Probe endpoints:

- `GET /livez` checks whether the API process is alive.
- `GET /readyz` checks whether PostgreSQL is reachable.
- `GET /v1/health` is the public versioned health contract.

Device session endpoints:

- `POST /v1/devices/register` creates an anonymous installation session.
- `POST /v1/devices/refresh` atomically rotates both opaque tokens.
- `DELETE /v1/devices/{device_id}` permanently deletes the authenticated device and its server data.

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
