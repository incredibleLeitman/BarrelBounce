<?php
// Copy this file to config.php next to api.php and fill in your values.
// config.php is listed in .gitignore and must never be committed.

return [
    // MySQL credentials from your hosting panel (KAS at all-inkl: Datenbanken).
    'db_host' => 'localhost',
    'db_name' => 'd0123456',
    'db_user' => 'd0123456',
    'db_pass' => 'change-me',

    // Long random string. The GitHub Actions verifier sends it to read pending
    // rows and to mark them verified. Put the same value in the repository secret
    // ADMIN_KEY. Generate one with: openssl rand -hex 32
    'admin_key' => 'change-me-to-a-long-random-string',

    // Limits (bytes / rows) to keep the API cheap to abuse.
    'max_level_bytes' => 262144,
    'max_taps' => 2000,
    'leaderboard_limit' => 20,
    'levels_page' => 30,
];
