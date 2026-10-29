-- Migration 002: verdict reasons, stars, per-player limits.
-- Run once on a database created from the previous schema.sql (phpMyAdmin > SQL).
-- A fresh install does not need this: schema.sql already contains everything.

ALTER TABLE levels ADD COLUMN reason VARCHAR(32) NOT NULL DEFAULT '' AFTER status;
ALTER TABLE runs   ADD COLUMN reason VARCHAR(32) NOT NULL DEFAULT '' AFTER status;
ALTER TABLE levels ADD KEY by_author (author_id, status);

CREATE TABLE IF NOT EXISTS stars (
  level_id      VARCHAR(64)  NOT NULL,
  player_id     VARCHAR(48)  NOT NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (level_id, player_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
