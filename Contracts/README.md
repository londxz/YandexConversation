# API Contracts

`openapi-v1.yaml` is the source of truth shared by the iOS application and the Go backend.

Rules:

- Implement handlers from the contract, not from duplicated structs or screenshots.
- Keep all public routes under `/v1`.
- Use `snake_case` JSON, UUID client-generated IDs, and RFC 3339 UTC timestamps.
- Return `X-Request-ID` on every HTTP response and the standard `ErrorEnvelope` on every error.
- Require `Idempotency-Key` where the contract declares it and persist its result for safe retries.
- Treat WebSocket events under `x-websocket-events` as part of the versioned public contract.
- Never add raw audio or transcript text to production logs, metrics, or traces.
- Additive changes are allowed in `v1`; breaking changes require a new API version.

Before merging backend changes, validate the OpenAPI document and run handler contract tests against its examples and schemas.
