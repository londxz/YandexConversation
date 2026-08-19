CREATE TABLE idempotency_keys (
    scope TEXT NOT NULL,
    key TEXT NOT NULL,
    request_hash BYTEA NOT NULL,
    response_status SMALLINT,
    response_headers JSONB,
    response_body BYTEA,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (scope, key),
    CONSTRAINT idempotency_keys_key_length CHECK (char_length(key) BETWEEN 16 AND 100),
    CONSTRAINT idempotency_keys_response_status CHECK (
        response_status IS NULL OR response_status BETWEEN 100 AND 599
    )
);

CREATE INDEX idempotency_keys_expires_at_idx ON idempotency_keys (expires_at);
