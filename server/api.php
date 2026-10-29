<?php
// BarrelBounce online API: leaderboards and community levels.
// Plain PHP + PDO/MySQL, one file, no framework, works on shared hosting.
//
// Every call is  api.php?action=NAME  with a JSON body for POST actions and
// returns JSON {"ok": true, ...} or {"ok": false, "error": "..."}.
//
//   GET  leaderboard   level_id, rev [, player_id]      verified runs, fastest first
//   GET  records       ids=level_id:rev,...              the fastest verified run per level (world records)
//   POST submit_run    {level_id, rev, player_id, player_name, player_color, ticks, taps[]}
//   GET  levels        [offset] [, player_id]           community levels: own first, then starred, newest first
//   GET  level         id [, player_id]                 one level's data (counts a play)
//   POST publish_level {level: {...full level JSON incl. verified proof...}}
//   GET  my_levels     player_id                        status of the player's published levels
//   POST unpublish     {level_id, player_id}            removes a level (also cancels a pending one)
//   POST star          {level_id, player_id, on}        marks / unmarks a favourite
//   GET  pending       key                              rows the verifier must replay
//   POST resolve       {key, runs:[{id,status,reason}], levels:[{id,status,reason}]}
//
// Runs and levels are stored as "pending" and only shown once the verifier
// (tools/verify_runs.gd, run by the GitHub Actions workflow) replayed them.
// A player may have one level pending at a time and at most max_levels_per_player
// published; failures carry a machine-readable "code" next to the message.

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$config = @include __DIR__ . '/config.php';
if (!is_array($config)) {
    fail('Server is not configured (config.php missing).', 500);
}

try {
    $pdo = new PDO(
        "mysql:host={$config['db_host']};dbname={$config['db_name']};charset=utf8mb4",
        $config['db_user'],
        $config['db_pass'],
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
    );
} catch (Exception $e) {
    fail('Database connection failed.', 500);
}

$action = $_GET['action'] ?? '';
$body = [];
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $raw = file_get_contents('php://input');
    if (strlen($raw) > $config['max_level_bytes'] + 65536) {
        fail('Request too large.', 413);
    }
    $body = json_decode($raw, true);
    if (!is_array($body)) {
        fail('Body must be JSON.');
    }
}

switch ($action) {
    case 'leaderboard':   leaderboard($pdo, $config); break;
    case 'records':       records($pdo); break;
    case 'submit_run':    submit_run($pdo, $config, $body); break;
    case 'levels':        list_levels($pdo, $config); break;
    case 'level':         get_level($pdo); break;
    case 'publish_level': publish_level($pdo, $config, $body); break;
    case 'my_levels':     my_levels($pdo, $config); break;
    case 'unpublish':     unpublish($pdo, $body); break;
    case 'star':          star($pdo, $body); break;
    case 'pending':       pending($pdo, $config); break;
    case 'resolve':       resolve($pdo, $config, $body); break;
    default:              fail('Unknown action.', 404);
}

// ---------------------------------------------------------------- actions

function leaderboard(PDO $pdo, array $config): void {
    $level_id = str_param($_GET['level_id'] ?? '', 64);
    $rev = str_param($_GET['rev'] ?? '', 16);
    $player_id = str_param($_GET['player_id'] ?? '', 48);
    if ($level_id === '' || $rev === '') {
        fail('level_id and rev are required.');
    }
    $limit = (int)$config['leaderboard_limit'];
    $st = $pdo->prepare("SELECT player_id, player_name, player_color, ticks, taps, created_at
                         FROM runs WHERE level_id = ? AND rev = ? AND status = 'verified'
                         ORDER BY ticks ASC, created_at DESC LIMIT $limit");
    $st->execute([$level_id, $rev]);
    $rows = [];
    $rank = 0;
    foreach ($st as $r) {
        // On equal times the newer run ranks higher, so a record can be re-taken.
        $rank++;
        $rows[] = [
            'rank' => $rank,
            'player_id' => $r['player_id'],
            'player_name' => $r['player_name'],
            'player_color' => $r['player_color'],
            'ticks' => (int)$r['ticks'],
            'taps' => json_decode($r['taps'], true) ?: [],
        ];
    }
    $mine = null;
    if ($player_id !== '') {
        $st = $pdo->prepare("SELECT ticks, status, reason, created_at FROM runs WHERE level_id = ? AND rev = ? AND player_id = ?");
        $st->execute([$level_id, $rev, $player_id]);
        $m = $st->fetch();
        if ($m) {
            $st = $pdo->prepare("SELECT COUNT(*) FROM runs WHERE level_id = ? AND rev = ? AND status = 'verified'
                                 AND (ticks < ? OR (ticks = ? AND created_at > ?))");
            $st->execute([$level_id, $rev, (int)$m['ticks'], (int)$m['ticks'], $m['created_at']]);
            $mine = ['ticks' => (int)$m['ticks'], 'status' => $m['status'], 'reason' => $m['reason'], 'rank' => (int)$st->fetchColumn() + 1];
        }
    }
    $st = $pdo->prepare("SELECT COUNT(*) FROM runs WHERE level_id = ? AND rev = ? AND status = 'verified'");
    $st->execute([$level_id, $rev]);
    ok(['rows' => $rows, 'mine' => $mine, 'total' => (int)$st->fetchColumn()]);
}

// World records for a list of levels, for the level lists: id -> fastest verified run.
function records(PDO $pdo): void {
    $ids = str_param($_GET['ids'] ?? '', 4000);
    $out = [];
    $st = $pdo->prepare("SELECT ticks, player_id, player_name, player_color,
                                (SELECT COUNT(*) FROM runs r2 WHERE r2.level_id = runs.level_id AND r2.rev = runs.rev AND r2.status = 'verified') AS total
                         FROM runs WHERE level_id = ? AND rev = ? AND status = 'verified'
                         ORDER BY ticks ASC, created_at DESC LIMIT 1");
    foreach (array_slice(array_filter(explode(',', $ids)), 0, 60) as $pair) {
        $parts = explode(':', $pair, 2);
        if (count($parts) !== 2) continue;
        $st->execute([str_param($parts[0], 64), str_param($parts[1], 16)]);
        $r = $st->fetch();
        if ($r) {
            $out[$parts[0]] = ['ticks' => (int)$r['ticks'], 'player_id' => $r['player_id'],
                'player_name' => $r['player_name'], 'player_color' => $r['player_color'], 'total' => (int)$r['total']];
        }
    }
    ok(['records' => (object)$out]);
}

function submit_run(PDO $pdo, array $config, array $b): void {
    $level_id = str_param($b['level_id'] ?? '', 64);
    $rev = str_param($b['rev'] ?? '', 16);
    $player_id = str_param($b['player_id'] ?? '', 48);
    $player_name = str_param($b['player_name'] ?? 'Player', 64);
    $player_color = color_param($b['player_color'] ?? '#ffd166');
    $ticks = (int)($b['ticks'] ?? 0);
    $taps = $b['taps'] ?? null;
    if ($level_id === '' || $rev === '' || $player_id === '' || $ticks <= 0 || !is_array($taps) || count($taps) === 0) {
        fail('level_id, rev, player_id, ticks and taps are required.');
    }
    if (count($taps) > $config['max_taps']) {
        fail('Too many taps.');
    }
    $clean = [];
    foreach ($taps as $t) {
        if (!is_numeric($t)) fail('taps must be numbers.');
        $clean[] = (int)$t;
    }
    // Only builtin levels and published levels can have a leaderboard.
    if (!preg_match('/^builtin_\d+$/', $level_id)) {
        $st = $pdo->prepare("SELECT rev FROM levels WHERE id = ?");
        $st->execute([$level_id]);
        $lv = $st->fetch();
        if (!$lv) fail('Unknown level. Publish it first.');
    }
    // One row per player and revision; a slower submission never replaces a faster one.
    $st = $pdo->prepare("SELECT id, ticks, status FROM runs WHERE level_id = ? AND rev = ? AND player_id = ?");
    $st->execute([$level_id, $rev, $player_id]);
    $existing = $st->fetch();
    if ($existing && (int)$existing['ticks'] <= $ticks && $existing['status'] !== 'rejected') {
        ok(['stored' => false, 'reason' => 'not faster than your stored run']);
    }
    if ($existing) {
        $st = $pdo->prepare("UPDATE runs SET player_name = ?, player_color = ?, ticks = ?, taps = ?, status = 'pending', reason = '', created_at = NOW() WHERE id = ?");
        $st->execute([$player_name, $player_color, $ticks, json_encode($clean), $existing['id']]);
    } else {
        $st = $pdo->prepare("INSERT INTO runs (level_id, rev, player_id, player_name, player_color, ticks, taps) VALUES (?, ?, ?, ?, ?, ?, ?)");
        $st->execute([$level_id, $rev, $player_id, $player_name, $player_color, $ticks, json_encode($clean)]);
    }
    ok(['stored' => true, 'status' => 'pending']);
}

function list_levels(PDO $pdo, array $config): void {
    $offset = max(0, (int)($_GET['offset'] ?? 0));
    $player_id = str_param($_GET['player_id'] ?? '', 48);
    $page = (int)$config['levels_page'];
    // Everyone sees verified levels; the author also sees their own pending / rejected ones.
    // Order: the player's own levels, then the ones they starred, then newest first.
    $st = $pdo->prepare("SELECT l.id, l.rev, l.name, l.author_id, l.author_name, l.author_color, l.proof_ticks,
                                l.status, l.reason, l.plays, l.created_at,
                                (SELECT COUNT(*) FROM stars s WHERE s.level_id = l.id) AS stars,
                                EXISTS(SELECT 1 FROM stars s WHERE s.level_id = l.id AND s.player_id = ?) AS starred
                         FROM levels l
                         WHERE l.status = 'verified' OR (l.author_id = ? AND ? <> '')
                         ORDER BY (l.author_id = ?) DESC, starred DESC, l.created_at DESC
                         LIMIT $page OFFSET $offset");
    $st->execute([$player_id, $player_id, $player_id, $player_id]);
    $rows = [];
    foreach ($st as $r) {
        $r['proof_ticks'] = (int)$r['proof_ticks'];
        $r['plays'] = (int)$r['plays'];
        $r['stars'] = (int)$r['stars'];
        $r['starred'] = (bool)$r['starred'];
        $r['mine'] = $player_id !== '' && $r['author_id'] === $player_id;
        $rows[] = $r;
    }
    ok(['rows' => $rows, 'offset' => $offset, 'page' => $page]);
}

function get_level(PDO $pdo): void {
    $id = str_param($_GET['id'] ?? '', 64);
    $player_id = str_param($_GET['player_id'] ?? '', 48);
    $st = $pdo->prepare("SELECT data, status, author_id FROM levels WHERE id = ?");
    $st->execute([$id]);
    $r = $st->fetch();
    if (!$r || ($r['status'] !== 'verified' && $r['author_id'] !== $player_id)) fail('Level not found.', 404);
    $pdo->prepare("UPDATE levels SET plays = plays + 1 WHERE id = ?")->execute([$id]);
    ok(['level' => json_decode($r['data'], true)]);
}

function publish_level(PDO $pdo, array $config, array $b): void {
    $level = $b['level'] ?? null;
    if (!is_array($level)) fail('level is required.');
    $json = json_encode($level);
    if (strlen($json) > $config['max_level_bytes']) fail('Level too large.');
    $id = str_param($level['id'] ?? '', 64);
    $rev = str_param($level['rev_hint'] ?? '', 16);   // the client sends its hash; the verifier recomputes it
    $name = str_param($level['name'] ?? 'Untitled', 80);
    $author_id = str_param($level['author_id'] ?? '', 48);
    $author_name = str_param($level['author'] ?? 'Player', 64);
    $v = $level['verified'] ?? null;
    if ($id === '' || $author_id === '' || !is_array($v) || !is_array($v['taps'] ?? null)) {
        fail('A level needs an id, an author_id and a verified proof run.');
    }
    if (!is_array($level['cannons'] ?? null) || count($level['cannons']) === 0) fail('No cannons.');
    if (preg_match('/^builtin_/', $id)) fail('Built-in ids cannot be published.');
    $author_color = color_param($v['color'] ?? '#ffd166');
    $proof_ticks = (int)($v['ticks'] ?? 0);
    if ($rev === '') $rev = str_param($v['rev'] ?? '', 16);
    $st = $pdo->prepare("SELECT author_id FROM levels WHERE id = ?");
    $st->execute([$id]);
    $existing = $st->fetch();
    if ($existing && $existing['author_id'] !== $author_id) fail('This level id belongs to another author.', 403);
    // One submission at a time per player, and a cap on published levels (pending ones count).
    $st = $pdo->prepare("SELECT COUNT(*) FROM levels WHERE author_id = ? AND status = 'pending' AND id <> ?");
    $st->execute([$author_id, $id]);
    if ((int)$st->fetchColumn() > 0) {
        fail('You already have a level waiting for verification. Wait for it or cancel it first.', 409, 'pending_exists');
    }
    $max = (int)($config['max_levels_per_player'] ?? 3);
    if (!$existing) {
        $st = $pdo->prepare("SELECT COUNT(*) FROM levels WHERE author_id = ?");
        $st->execute([$author_id]);
        if ((int)$st->fetchColumn() >= $max) {
            fail("You can have at most $max published levels. Unpublish one first.", 409, 'limit');
        }
    }
    if ($existing) {
        // Re-publishing replaces the level; the old revision's runs stay stored but no
        // longer apply because the leaderboard is per revision.
        $st = $pdo->prepare("UPDATE levels SET rev = ?, name = ?, author_name = ?, author_color = ?, data = ?, proof_ticks = ?, status = 'pending', reason = '' WHERE id = ?");
        $st->execute([$rev, $name, $author_name, $author_color, $json, $proof_ticks, $id]);
    } else {
        $st = $pdo->prepare("INSERT INTO levels (id, rev, name, author_id, author_name, author_color, data, proof_ticks) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
        $st->execute([$id, $rev, $name, $author_id, $author_name, $author_color, $json, $proof_ticks]);
    }
    ok(['stored' => true, 'status' => 'pending']);
}

function my_levels(PDO $pdo, array $config): void {
    $player_id = str_param($_GET['player_id'] ?? '', 48);
    if ($player_id === '') fail('player_id is required.');
    $st = $pdo->prepare("SELECT id, rev, name, status, reason, plays, created_at,
                                (SELECT COUNT(*) FROM stars s WHERE s.level_id = levels.id) AS stars
                         FROM levels WHERE author_id = ? ORDER BY created_at DESC");
    $st->execute([$player_id]);
    $rows = [];
    $pending = false;
    foreach ($st as $r) {
        $r['plays'] = (int)$r['plays'];
        $r['stars'] = (int)$r['stars'];
        if ($r['status'] === 'pending') $pending = true;
        $rows[] = $r;
    }
    ok(['rows' => $rows, 'count' => count($rows), 'pending' => $pending,
        'max' => (int)($config['max_levels_per_player'] ?? 3)]);
}

// Removes a level together with its runs and stars. Also how a pending submission is cancelled.
function unpublish(PDO $pdo, array $b): void {
    $id = str_param($b['level_id'] ?? '', 64);
    $player_id = str_param($b['player_id'] ?? '', 48);
    if ($id === '' || $player_id === '') fail('level_id and player_id are required.');
    $st = $pdo->prepare("SELECT author_id, status FROM levels WHERE id = ?");
    $st->execute([$id]);
    $r = $st->fetch();
    if (!$r) ok(['removed' => false]);
    if ($r['author_id'] !== $player_id) fail('This level belongs to another author.', 403);
    $pdo->prepare("DELETE FROM runs WHERE level_id = ?")->execute([$id]);
    $pdo->prepare("DELETE FROM stars WHERE level_id = ?")->execute([$id]);
    $pdo->prepare("DELETE FROM levels WHERE id = ?")->execute([$id]);
    ok(['removed' => true, 'was' => $r['status']]);
}

function star(PDO $pdo, array $b): void {
    $id = str_param($b['level_id'] ?? '', 64);
    $player_id = str_param($b['player_id'] ?? '', 48);
    $on = !empty($b['on']);
    if ($id === '' || $player_id === '') fail('level_id and player_id are required.');
    $st = $pdo->prepare("SELECT author_id, status FROM levels WHERE id = ?");
    $st->execute([$id]);
    $r = $st->fetch();
    if (!$r || $r['status'] !== 'verified') fail('Level not found.', 404);
    if ($r['author_id'] === $player_id) fail('You cannot star your own level.');
    if ($on) {
        $pdo->prepare("INSERT IGNORE INTO stars (level_id, player_id) VALUES (?, ?)")->execute([$id, $player_id]);
    } else {
        $pdo->prepare("DELETE FROM stars WHERE level_id = ? AND player_id = ?")->execute([$id, $player_id]);
    }
    $st = $pdo->prepare("SELECT COUNT(*) FROM stars WHERE level_id = ?");
    $st->execute([$id]);
    ok(['starred' => $on, 'stars' => (int)$st->fetchColumn()]);
}

function pending(PDO $pdo, array $config): void {
    require_admin($config, $_GET['key'] ?? '');
    $runs = [];
    $st = $pdo->query("SELECT id, level_id, rev, ticks, taps FROM runs WHERE status = 'pending' ORDER BY created_at ASC LIMIT 200");
    foreach ($st as $r) {
        $r['id'] = (int)$r['id'];
        $r['ticks'] = (int)$r['ticks'];
        $r['taps'] = json_decode($r['taps'], true) ?: [];
        $runs[] = $r;
    }
    $levels = [];
    $st = $pdo->query("SELECT id, rev, data FROM levels WHERE status = 'pending' ORDER BY created_at ASC LIMIT 50");
    foreach ($st as $r) {
        $levels[] = ['id' => $r['id'], 'rev' => $r['rev'], 'data' => json_decode($r['data'], true)];
    }
    // The verifier also needs the data of verified levels that pending runs refer to.
    $need = [];
    foreach ($runs as $r) {
        if (!preg_match('/^builtin_/', $r['level_id'])) $need[$r['level_id']] = true;
    }
    $level_data = [];
    foreach (array_keys($need) as $lid) {
        $st = $pdo->prepare("SELECT data FROM levels WHERE id = ?");
        $st->execute([$lid]);
        $r = $st->fetch();
        if ($r) $level_data[$lid] = json_decode($r['data'], true);
    }
    // (object) keeps an empty map a JSON object instead of [].
    ok(['runs' => $runs, 'levels' => $levels, 'level_data' => (object)$level_data]);
}

function resolve(PDO $pdo, array $config, array $b): void {
    require_admin($config, $b['key'] ?? '');
    $n = 0;
    foreach (($b['runs'] ?? []) as $r) {
        $status = ($r['status'] ?? '') === 'verified' ? 'verified' : 'rejected';
        $reason = $status === 'verified' ? '' : str_param($r['reason'] ?? '', 32);
        $st = $pdo->prepare("UPDATE runs SET status = ?, reason = ? WHERE id = ? AND status = 'pending'");
        $st->execute([$status, $reason, (int)($r['id'] ?? 0)]);
        $n += $st->rowCount();
    }
    foreach (($b['levels'] ?? []) as $l) {
        $status = ($l['status'] ?? '') === 'verified' ? 'verified' : 'rejected';
        $reason = $status === 'verified' ? '' : str_param($l['reason'] ?? '', 32);
        $st = $pdo->prepare("UPDATE levels SET status = ?, reason = ? WHERE id = ? AND status = 'pending'");
        $st->execute([$status, $reason, str_param($l['id'] ?? '', 64)]);
        $n += $st->rowCount();
    }
    ok(['updated' => $n]);
}

// ---------------------------------------------------------------- helpers

function require_admin(array $config, string $key): void {
    if ($key === '' || !hash_equals((string)$config['admin_key'], $key)) {
        fail('Forbidden.', 403);
    }
}

function str_param($v, int $max): string {
    $s = is_string($v) ? trim($v) : '';
    return mb_substr($s, 0, $max);
}

function color_param($v): string {
    return (is_string($v) && preg_match('/^#[0-9a-fA-F]{6}$/', $v)) ? strtolower($v) : '#ffd166';
}

function ok(array $data): void {
    echo json_encode(['ok' => true] + $data);
    exit;
}

function fail(string $message, int $code = 400, string $error_code = ''): void {
    http_response_code($code);
    $out = ['ok' => false, 'error' => $message];
    if ($error_code !== '') $out['code'] = $error_code;
    echo json_encode($out);
    exit;
}
