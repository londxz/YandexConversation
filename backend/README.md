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
set +a
go run ./cmd/api
```

The application does not read `.env` automatically. Production configuration must come from the deployment environment or secret manager.

## Validation

```bash
make check
```

This runs formatting, `go vet`, race-enabled tests, and a full build.

## Privacy

Never add raw audio, transcript text, authorization tokens, or request bodies to logs. Request logs contain only metadata such as method, path, status, duration, and request ID.
