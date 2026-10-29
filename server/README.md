# BarrelBounce online API (leaderboards and community levels)

A single PHP file plus a MySQL database. Works on shared hosting such as all-inkl.
Verification of every submitted run is done by the repository's GitHub Actions workflow
`verify.yml`, which replays the taps with the game's own simulation, so the server never
trusts a client's time.

## Set up on all-inkl (once, ~15 minutes)

1. **Database.** In KAS go to *Datenbanken* and create one. Note host (usually `localhost`),
   database name, user and password. Open phpMyAdmin for it and import `schema.sql`.
2. **Files.** Upload `api.php` to a folder on your webspace, for example
   `/barrelbounce/api.php`, so it is reachable as `https://YOURDOMAIN/barrelbounce/api.php`.
   Copy `config.example.php` to `config.php` in the same folder and fill in the database
   values and a long random `admin_key` (for example from `openssl rand -hex 32`).
   Make sure PHP 8 is selected for the domain in KAS (*PHP-Version*). Upload `.htaccess`
   too: it stops the web server from ever handing out `config.php` or `schema.sql`.
3. **Check.** Open `https://YOURDOMAIN/barrelbounce/api.php?action=levels` in a browser.
   You should see `{"ok":true,"rows":[],...}`.
4. **Game.** In `scripts/online.gd` set `API_URL` to that address and push. The web build
   picks it up on the next deploy; desktop and mobile builds on the next export.
5. **Verifier.** In the GitHub repository add two secrets under *Settings → Secrets and
   variables → Actions*: `API_URL` (the same address) and `ADMIN_KEY` (the value from
   `config.php`). The workflow then runs every 30 minutes and can be started by hand under
   *Actions → Verify online runs → Run workflow*.

## What the game does with it

- Finishing a level with a new personal best posts the run (`submit_run`). It is stored as
  *pending* and appears on the leaderboard once verified. The win panel shows the top of the
  leaderboard and your rank.
- *Publish* on one of your levels in the level select uploads it (`publish_level`) with your
  proof run. It appears under *Community* for everyone once verified. Re-publishing an edited
  level replaces it; the old times no longer apply because the revision changed.
- The *Community* tab lists verified levels; *Play* downloads the level and keeps it in a local
  cache. Runs on community levels go to the same leaderboard table.

## API

All actions: `api.php?action=NAME`. POST bodies are JSON. Responses are JSON with `ok`.

| action | method | parameters |
|---|---|---|
| `leaderboard` | GET | `level_id`, `rev`, optional `player_id` → `rows`, `mine`, `total` |
| `submit_run` | POST | `level_id`, `rev`, `player_id`, `player_name`, `player_color`, `ticks`, `taps[]` |
| `levels` | GET | `offset` → verified levels, newest first |
| `level` | GET | `id` → the level JSON |
| `publish_level` | POST | `level` (full level JSON with `verified` proof) |
| `pending` | GET | `key` → pending runs and levels for the verifier |
| `resolve` | POST | `key`, `runs[]`, `levels[]` with `status` verified / rejected |

Everything is CORS-enabled so the web build on GitHub Pages can call it.

## Abuse notes

There is no login: a player is identified by the random id in their profile, which is also
what ties runs to names and colours. Nothing a client sends is trusted for ranking until the
verifier replayed it, so a forged time never reaches the board. Spam is limited by size
checks and one row per player and level revision; if it ever becomes a problem, put the
folder behind a hosting-level rate limit.
