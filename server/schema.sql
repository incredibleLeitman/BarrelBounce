-- BarrelBounce online API: MySQL / MariaDB schema.
-- Import once (phpMyAdmin > Import, or `mysql -u USER -p DB < schema.sql`).
-- Existing databases from before migrate_001.sql: run that file instead.

CREATE TABLE IF NOT EXISTS levels (
  id            VARCHAR(64)  NOT NULL PRIMARY KEY,   -- the level's own id (user_...)
  rev           CHAR(16)     NOT NULL,               -- revision hash of the gameplay content
  name          VARCHAR(80)  NOT NULL,
  author_id     VARCHAR(48)  NOT NULL,
  author_name   VARCHAR(64)  NOT NULL,
  author_color  VARCHAR(9)   NOT NULL DEFAULT '#ffd166',
  data          MEDIUMTEXT   NOT NULL,               -- full level JSON incl. the proof run
  proof_ticks   INT          NOT NULL,
  status        ENUM('pending','verified','rejected') NOT NULL DEFAULT 'pending',
  reason        VARCHAR(32)  NOT NULL DEFAULT '',    -- verifier's code when rejected
  plays         INT          NOT NULL DEFAULT 0,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY listing (status, created_at),
  KEY by_author (author_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS runs (
  id            INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
  level_id      VARCHAR(64)  NOT NULL,               -- builtin_xx or a published level id
  rev           CHAR(16)     NOT NULL,
  player_id     VARCHAR(48)  NOT NULL,
  player_name   VARCHAR(64)  NOT NULL,
  player_color  VARCHAR(9)   NOT NULL DEFAULT '#ffd166',
  ticks         INT          NOT NULL,
  taps          TEXT         NOT NULL,               -- JSON array of tick numbers
  status        ENUM('pending','verified','rejected') NOT NULL DEFAULT 'pending',
  reason        VARCHAR(32)  NOT NULL DEFAULT '',
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY one_per_player (level_id, rev, player_id),
  KEY board (level_id, rev, status, ticks),
  KEY pending (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- A player's favourite community levels (one row per player and level).
CREATE TABLE IF NOT EXISTS stars (
  level_id      VARCHAR(64)  NOT NULL,
  player_id     VARCHAR(48)  NOT NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (level_id, player_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
