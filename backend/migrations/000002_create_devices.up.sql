CREATE TABLE devices (
    id UUID PRIMARY KEY,
    platform TEXT NOT NULL,
    app_version TEXT NOT NULL,
    locale TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT devices_platform CHECK (platform = 'ios'),
    CONSTRAINT devices_app_version_length CHECK (char_length(app_version) BETWEEN 1 AND 64),
    CONSTRAINT devices_locale_length CHECK (char_length(locale) BETWEEN 2 AND 35)
);

CREATE TABLE device_sessions (
    id UUID PRIMARY KEY,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    access_token_hash BYTEA NOT NULL UNIQUE,
    refresh_token_hash BYTEA NOT NULL UNIQUE,
    access_expires_at TIMESTAMPTZ NOT NULL,
    refresh_expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    CONSTRAINT device_sessions_access_hash_length CHECK (octet_length(access_token_hash) = 32),
    CONSTRAINT device_sessions_refresh_hash_length CHECK (octet_length(refresh_token_hash) = 32),
    CONSTRAINT device_sessions_expiry_order CHECK (refresh_expires_at > access_expires_at),
    CONSTRAINT device_sessions_revocation_time CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);

ALTER TABLE idempotency_keys
    ADD COLUMN owner_device_id UUID,
    ADD CONSTRAINT idempotency_keys_owner_device_fk
        FOREIGN KEY (owner_device_id)
        REFERENCES devices(id)
        ON DELETE CASCADE
        DEFERRABLE INITIALLY DEFERRED;

CREATE INDEX idempotency_keys_owner_device_id_idx
    ON idempotency_keys (owner_device_id)
    WHERE owner_device_id IS NOT NULL;

CREATE INDEX device_sessions_device_id_idx ON device_sessions (device_id);
CREATE INDEX device_sessions_access_expiry_idx ON device_sessions (access_expires_at)
    WHERE revoked_at IS NULL;
CREATE INDEX device_sessions_refresh_expiry_idx ON device_sessions (refresh_expires_at)
    WHERE revoked_at IS NULL;
