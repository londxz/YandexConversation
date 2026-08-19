ALTER TABLE idempotency_keys DROP COLUMN IF EXISTS owner_device_id;
DROP TABLE IF EXISTS device_sessions;
DROP TABLE IF EXISTS devices;
