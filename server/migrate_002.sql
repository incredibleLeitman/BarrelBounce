-- Migration 002: anonymous usage events (api.php track / stats).
-- Run once on a database that already has migrate_001.sql applied (phpMyAdmin > SQL).

CREATE TABLE IF NOT EXISTS events (
  id            INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
  session       CHAR(16)     NOT NULL,
  build         VARCHAR(8)   NOT NULL DEFAULT '',
  platform      VARCHAR(16)  NOT NULL DEFAULT '',
  version       VARCHAR(16)  NOT NULL DEFAULT '',
  name          VARCHAR(24)  NOT NULL,
  level_id      VARCHAR(64)  NOT NULL DEFAULT '',
  value         INT          NOT NULL DEFAULT 0,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY by_name (name, created_at),
  KEY by_level (level_id, name),
  KEY by_session (session)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
