<?php
declare(strict_types=1);

/*
 * fragebogenpi Wartezimmer-Server
 *
 * Liest pro Anfrage genau die aelteste GDT-Datei aus dem separaten
 * Wartezimmer-Share, gibt ausschliesslich die konfigurierte Namensdarstellung
 * und das aus dem Dateinamen abgeleitete Ziel aus und loescht die GDT-Datei.
 */

error_reporting(0);
ini_set('display_errors', '0');
ini_set('log_errors', '0');

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('X-Content-Type-Options: nosniff');

function finish_empty(int $status): never
{
    http_response_code($status);
    exit;
}

function value_to_utf8(string $value): string
{
    $value = trim($value);
    if ($value === '' || preg_match('//u', $value) === 1) {
        return $value;
    }

    if (function_exists('iconv')) {
        $converted = @iconv('Windows-1252', 'UTF-8//IGNORE', $value);
        if (is_string($converted)) {
            return trim($converted);
        }
    }

    return preg_replace('/[^\x20-\x7E]/', '', $value) ?? '';
}

function parse_patient_name(string $gdt): array
{
    $firstName = '';
    $lastName = '';

    foreach (preg_split('/\r\n|\n|\r/', $gdt) ?: [] as $line) {
        if (strlen($line) < 7 || !ctype_digit(substr($line, 0, 7))) {
            continue;
        }

        $field = substr($line, 3, 4);
        $value = value_to_utf8(substr($line, 7));

        if ($field === '3102' && $value !== '') {
            $firstName = $value;
        } elseif ($field === '3101' && $value !== '') {
            $lastName = $value;
        }

        if ($firstName !== '' && $lastName !== '') {
            break;
        }
    }

    return [$firstName, $lastName];
}

function shorten_name_part(string $value, bool $shorten, int $letters, bool $dot): string
{
    $value = trim($value);
    if ($value === '' || !$shorten) {
        return $value;
    }

    $lettersOnly = preg_replace('/[\s\p{Pd}]+/u', '', $value) ?? '';
    $characters = preg_split('//u', $lettersOnly, -1, PREG_SPLIT_NO_EMPTY) ?: [];
    $short = implode('', array_slice($characters, 0, $letters));

    if ($short !== '' && $dot) {
        $short .= '.';
    }

    return $short;
}

function target_from_filename(string $filename): string
{
    $target = pathinfo($filename, PATHINFO_FILENAME);
    $target = str_replace('_', ' ', $target);
    $target = preg_replace('/\s+/u', ' ', trim($target)) ?? '';
    return $target !== '' ? $target : 'Wartezimmer';
}

$requestMethod = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($requestMethod !== 'GET' && $requestMethod !== 'HEAD') {
    header('Allow: GET, HEAD');
    finish_empty(405);
}

$configFile = '/etc/fragebogenpi/wartezimmer-config.php';
if (!is_file($configFile)) {
    finish_empty(503);
}

$config = require $configFile;
if (!is_array($config)) {
    finish_empty(503);
}

$shareDir = (string)($config['share_dir'] ?? '');
$lockFile = (string)($config['lock_file'] ?? '');
if ($shareDir === '' || $lockFile === '' || !is_dir($shareDir)) {
    finish_empty(503);
}

if ($requestMethod === 'HEAD') {
    finish_empty(204);
}

$lock = @fopen($lockFile, 'c');
if ($lock === false || !@flock($lock, LOCK_EX)) {
    finish_empty(503);
}

$files = [];
try {
    foreach (new DirectoryIterator($shareDir) as $entry) {
        if ($entry->isDot() || $entry->isLink() || !$entry->isFile()) {
            continue;
        }

        $filename = $entry->getFilename();
        if (str_starts_with($filename, '.') || strtolower($entry->getExtension()) !== 'gdt') {
            continue;
        }

        $files[] = [
            'path' => $entry->getPathname(),
            'name' => $filename,
            'mtime' => $entry->getMTime(),
        ];
    }
} catch (Throwable) {
    @flock($lock, LOCK_UN);
    @fclose($lock);
    finish_empty(503);
}

if ($files === []) {
    @flock($lock, LOCK_UN);
    @fclose($lock);
    finish_empty(204);
}

usort($files, static function (array $a, array $b): int {
    $timeOrder = $a['mtime'] <=> $b['mtime'];
    return $timeOrder !== 0 ? $timeOrder : strnatcasecmp($a['name'], $b['name']);
});

$selected = $files[0];
$gdt = @file_get_contents($selected['path']);
if (!is_string($gdt)) {
    @flock($lock, LOCK_UN);
    @fclose($lock);
    finish_empty(500);
}

[$firstName, $lastName] = parse_patient_name($gdt);

$first = shorten_name_part(
    $firstName,
    (bool)($config['shorten_first_name'] ?? true),
    max(1, (int)($config['first_name_letters'] ?? 1)),
    (bool)($config['first_name_dot'] ?? true)
);
$last = shorten_name_part(
    $lastName,
    (bool)($config['shorten_last_name'] ?? true),
    max(1, (int)($config['last_name_letters'] ?? 2)),
    (bool)($config['last_name_dot'] ?? true)
);

$displayText = trim($first . ' ' . $last);
if ($displayText === '') {
    $displayText = 'Aufruf';
}

$payload = [
    'display_text' => $displayText,
    'target' => target_from_filename($selected['name']),
];
$json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
if ($json === false || !@unlink($selected['path'])) {
    @flock($lock, LOCK_UN);
    @fclose($lock);
    finish_empty(500);
}

@flock($lock, LOCK_UN);
@fclose($lock);

http_response_code(200);
echo $json;
