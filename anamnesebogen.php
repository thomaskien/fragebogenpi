<?php
declare(strict_types=1);

/*
 * anamnesebogen.php v1.2.1
 *
 * Changelog (since v1.2)
 * - v1.2.1:
 *   + Fix Packyears: yes/no werden intern als "yes"/"no" gespeichert (kompatibel zu YAML show_if)
 *   + Fix Packyears: derived-Ausgabe funktioniert jetzt zuverlässig (auch wenn show_if aktiv ist)
 *   + Packyears-Rundung: "mind." + Abrunden (floor) auf ganze Packyears
 *
 * (Older history)
 * - v1.0: Übernahme aus befund.php (Grundworkflow): Auftrags-GDT finden, Formular anzeigen, Antwort-GDT 6310 schreiben, Auftrags-GDT löschen
 *         + Hardcoded Top-Felder: Größe (3622), Gewicht (3623), Telefon 1 (3626), Telefon 2 (3618), E-Mail (3619)
 *         + Patientenstammdaten (Name, Geburtsdatum, Adresse) read-only aus Auftrags-GDT (Anzeige)
 *         + Fragebogen aus externer YAML-Datei (anamnesebogen.yaml)
 *         + Ausgabe in GDT (6228) nur für angekreuzte/aktive Angaben, gruppiert pro Sektion im Format:
 *             ---
 *             Überschrift
 *             ========
 *             - Eintrag 1
 *             - Eintrag 2
 * - v1.1: UI: Radios als Grid statt flex-wrap (iPad sauber)
 *         + UI: show_if aus YAML wird clientseitig angewendet (ein-/ausblenden)
 *         + Fix: choice-Auswertung robust
 * - v1.2:
 *         + Anzeige oben: Adresse entfernt
 *         + Geburtsdatum (3103) korrekt formatiert als DD.MM.YYYY (8 Ziffern, ggf. abgeschnitten)
 *         + Kontaktänderungen: zusätzlicher 6228-Block "Aktualisierte Kontaktinformationen" ganz oben, wenn abweichend
 *         + Packyears: aus Rauchen (Ø Zigaretten/Tag, Jahre) berechnen und als "mind. X Packyears" ausgeben
 *         + Alkohol: Feld "Getränke pro Woche" nur wenn Alkoholkonsum != nein
 */

$APP_FOOTER  = 'fragebogenpi von Dr. Thomas Kienzle 2026';
$APP_VERSION = 'v1.2.1 (anamnesebogen.php)';

$dirGdt = '/srv/fragebogenpi/GDT';

// Auftragsdatei (Request) ist fest:
$REQUEST_GDT_NAME = 'ANAT2MD.gdt';

// Antwortdatei:
$OUT_GDT_NAME = 'T2MDANA.gdt';

// YAML-Konfiguration (Fragen):
$YAML_PATH = __DIR__ . '/anamnesebogen.yaml';

// Default IDs falls 8315/8316 in der Request fehlen:
$DEFAULT_8315 = 'BOGI_GDT';  // 8315 soll BOGI_GDT sein
$DEFAULT_8316 = 'BIMP_GDT';

// Identität der Antwort (GDT 6200/6201):
$ANSWER_6200 = 'ANA1';
$ANSWER_6201 = 'KI-Anamnese';

// UI-Titel:
$UI_TITLE = 'Anamnese (iPad)';

// Maximale Länge pro 6228-Zeile (CP437-Bytes):
$MAX_6228_BYTES = 70;

// ----------------- helpers -----------------
function h(string $s): string { return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }

function json_out(int $code, array $payload): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');

    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        $json = json_encode([
            'status' => 'error',
            'message' => 'json_encode fehlgeschlagen',
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '{"status":"error","message":"json_encode failed"}';
    }

    echo $json;
    exit;
}

function gdt_line(string $field4, string $value): string {
    $rest = $field4 . $value;
    $len  = 3 + strlen($rest);
    return str_pad((string)$len, 3, '0', STR_PAD_LEFT) . $rest;
}

function parse_gdt(string $path): array {
    $raw = file_get_contents($path);
    if ($raw === false) return [];
    $raw = str_replace("\r\n", "\n", $raw);
    $lines = array_filter(explode("\n", $raw), fn($l) => trim($l) !== '');

    $fields = [];
    foreach ($lines as $line) {
        if (strlen($line) < 7) continue;
        $rest  = substr($line, 3);
        $field = substr($rest, 0, 4);
        $value = substr($rest, 4);
        $fields[$field] = $value;
    }
    return $fields;
}

function write_gdt_file(string $path, array $lines): void {
    $joined = implode("\n", $lines) . "\n";
    $totalBytes = strlen($joined);
    $total6 = str_pad((string)$totalBytes, 6, '0', STR_PAD_LEFT);

    foreach ($lines as $i => $line) {
        $rest = substr($line, 3);
        $field = substr($rest, 0, 4);
        if ($field === '8100') {
            $lines[$i] = gdt_line('8100', $total6);
            break;
        }
    }

    $joined2 = implode("\n", $lines) . "\n";
    $totalBytes2 = strlen($joined2);
    if ($totalBytes2 !== $totalBytes) {
        $total6b = str_pad((string)$totalBytes2, 6, '0', STR_PAD_LEFT);
        foreach ($lines as $i => $line) {
            $rest = substr($line, 3);
            $field = substr($rest, 0, 4);
            if ($field === '8100') {
                $lines[$i] = gdt_line('8100', $total6b);
                break;
            }
        }
        $joined2 = implode("\n", $lines) . "\n";
    }

    file_put_contents($path, $joined2);
}

function clean_utf8_text(string $s, int $maxLen = 200): string {
    $s = str_replace(["\r", "\n", "\t"], ' ', $s);
    $s = preg_replace('/\s+/', ' ', $s) ?? $s;
    $s = trim($s);

    if (function_exists('mb_substr')) {
        $s = mb_substr($s, 0, $maxLen, 'UTF-8');
    } else {
        $s = substr($s, 0, $maxLen);
    }

    if (function_exists('iconv')) {
        $fixed = @iconv('UTF-8', 'UTF-8//IGNORE', $s);
        if ($fixed !== false) $s = $fixed;
    }
    return $s;
}

function to_cp437_bytes(string $utf8): string {
    $utf8 = str_replace(["\r", "\n", "\t"], ' ', $utf8);
    $utf8 = preg_replace('/\s+/', ' ', $utf8) ?? $utf8;
    $utf8 = trim($utf8);

    if (function_exists('iconv')) {
        $conv = @iconv('UTF-8', 'CP437//TRANSLIT//IGNORE', $utf8);
        if ($conv !== false && $conv !== '') return $conv;
    }
    return preg_replace('/[^\x20-\x7E]/', '?', $utf8) ?? $utf8;
}

function wrap_cp437_lines(string $utf8Line, int $maxBytes, string $firstPrefix = '', string $nextPrefix = ''): array {
    $utf8Line = clean_utf8_text($utf8Line, 2000);

    $candidate = to_cp437_bytes($firstPrefix . $utf8Line);
    if (strlen($candidate) <= $maxBytes) return [$candidate];

    $words = preg_split('/\s+/', $utf8Line) ?: [];
    $lines = [];
    $current = '';
    $isFirst = true;

    foreach ($words as $w) {
        $try = ($current === '') ? $w : ($current . ' ' . $w);
        $prefix = $isFirst ? $firstPrefix : $nextPrefix;
        $encTry = to_cp437_bytes($prefix . $try);

        if (strlen($encTry) <= $maxBytes) {
            $current = $try;
            continue;
        }

        if ($current !== '') {
            $prefix2 = $isFirst ? $firstPrefix : $nextPrefix;
            $lines[] = to_cp437_bytes($prefix2 . $current);
            $isFirst = false;
            $current = $w;
            continue;
        }

        $encWord = to_cp437_bytes($prefix . $w);
        $lines[] = substr($encWord, 0, $maxBytes);
        $isFirst = false;
        $current = '';
    }

    if ($current !== '') {
        $prefix3 = $isFirst ? $firstPrefix : $nextPrefix;
        $lines[] = to_cp437_bytes($prefix3 . $current);
    }
    return $lines;
}

function yaml_load_or_die(string $path): array {
    if (!is_file($path)) return ['__error' => 'YAML-Datei nicht gefunden: ' . $path];
    if (!function_exists('yaml_parse_file')) return ['__error' => 'PHP YAML Extension fehlt (yaml_parse_file nicht verfügbar). Bitte php-yaml installieren.'];
    $data = @yaml_parse_file($path);
    if (!is_array($data)) return ['__error' => 'YAML konnte nicht geparst werden oder ist leer/ungültig.'];
    return $data;
}

// show_if: robust für bool und "yes"/"no"
function cond_ok(array $answers, ?array $cond): bool {
    if (!$cond) return true;
    $id = (string)($cond['id'] ?? '');
    if ($id === '') return true;
    $val = $answers[$id] ?? null;

    $eq = $cond['equals'] ?? null;
    $neq = $cond['not_equals'] ?? null;

    // bool <-> yes/no Kompatibilität
    if (is_bool($val)) {
        if ($eq === 'yes') $eq = true;
        if ($eq === 'no')  $eq = false;
        if ($neq === 'yes') $neq = true;
        if ($neq === 'no')  $neq = false;
    } elseif (is_string($val)) {
        if ($val === 'yes' && $eq === true) $eq = 'yes';
        if ($val === 'no'  && $eq === false) $eq = 'no';
        if ($val === 'yes' && $neq === true) $neq = 'yes';
        if ($val === 'no'  && $neq === false) $neq = 'no';
    }

    if (array_key_exists('equals', $cond)) return $val === $eq;
    if (array_key_exists('not_equals', $cond)) return $val !== $neq;
    return true;
}

function build_section_block_lines(string $title, array $bullets, int $maxBytes): array {
    $out = [];
    foreach (wrap_cp437_lines('---', $maxBytes) as $cp) $out[] = gdt_line('6228', $cp);
    foreach (wrap_cp437_lines($title, $maxBytes) as $cp) $out[] = gdt_line('6228', $cp);
    foreach (wrap_cp437_lines('========', $maxBytes) as $cp) $out[] = gdt_line('6228', $cp);
    foreach ($bullets as $b) {
        $b = clean_utf8_text($b, 600);
        foreach (wrap_cp437_lines($b, $maxBytes, '- ', '  ') as $cp) $out[] = gdt_line('6228', $cp);
    }
    return $out;
}

function section_bullets(array $section, array $answers): array {
    $bullets = [];

    if (isset($section['show_if']) && is_array($section['show_if'])) {
        if (!cond_ok($answers, $section['show_if'])) return [];
    }

    $type = (string)($section['type'] ?? '');
    $questions = $section['questions'] ?? [];
    if (!is_array($questions)) return [];

    if ($type === 'checklist') {
        foreach ($questions as $q) {
            if (!is_array($q)) continue;
            $id = (string)($q['id'] ?? '');
            $label = (string)($q['label'] ?? '');
            if ($id === '' || $label === '') continue;
            if (($answers[$id] ?? false) === true) $bullets[] = $label;
        }
        return $bullets;
    }

    foreach ($questions as $q) {
        if (!is_array($q)) continue;
        $id = (string)($q['id'] ?? '');
        $label = (string)($q['label'] ?? '');
        $qType = (string)($q['type'] ?? '');
        if ($id === '' || $label === '') continue;

        if (isset($q['show_if']) && is_array($q['show_if'])) {
            if (!cond_ok($answers, $q['show_if'])) continue;
        }

        $val = $answers[$id] ?? null;

        if ($qType === 'yesno') {
            if ($val === true || $val === 'yes') $bullets[] = $label;
            continue;
        }

        if ($qType === 'multiselect') {
            if (is_array($val) && count($val) > 0) {
                $direct = in_array($id, ['allergie_typen'], true);
                foreach ($val as $opt) {
                    $opt = clean_utf8_text((string)$opt, 200);
                    if ($opt === '') continue;
                    $bullets[] = $direct ? $opt : ($label . ': ' . $opt);
                }
            }
            continue;
        }

        if ($qType === 'choice') {
            $v = clean_utf8_text((string)$val, 200);
            if ($v === '' || $v === 'nein' || $v === 'normal' || $v === 'konstant') continue;
            $bullets[] = $label . ': ' . $v;
            continue;
        }

        if ($qType === 'number' || $qType === 'text') {
            $v = clean_utf8_text((string)$val, 600);
            if ($v === '') continue;
            $bullets[] = $label . ': ' . $v;
            continue;
        }

        if ($qType === 'derived') {
            if ($id === 'packyears') {
                $v = clean_utf8_text((string)($answers['_packyears_text'] ?? ''), 200);
                if ($v !== '') $bullets[] = $v;
            }
            continue;
        }

        if ($val === true) $bullets[] = $label;
    }

    return $bullets;
}

function build_6228_blocks(array $yaml, array $answers, int $maxBytes): array {
    $out = [];
    $sections = $yaml['sections'] ?? [];
    if (!is_array($sections)) return [];

    foreach ($sections as $sec) {
        if (!is_array($sec)) continue;
        $title = clean_utf8_text((string)($sec['title'] ?? ''), 200);
        if ($title === '') continue;

        $bullets = section_bullets($sec, $answers);
        if (count($bullets) === 0) continue;

        $out = array_merge($out, build_section_block_lines($title, $bullets, $maxBytes));
    }
    return $out;
}

function norm_contact(string $s): string {
    $s = clean_utf8_text($s, 200);
    $s = preg_replace('/\s+/', ' ', $s) ?? $s;
    return trim($s);
}

function format_gebdat(string $s): string {
    $digits = preg_replace('/\D+/', '', $s) ?? '';
    if (strlen($digits) >= 8) $digits = substr($digits, 0, 8);
    if (strlen($digits) !== 8) return ($s !== '' ? $s : '—');
    return substr($digits, 0, 2) . '.' . substr($digits, 2, 2) . '.' . substr($digits, 4, 4);
}

function parse_float_de(string $s): ?float {
    $s = trim($s);
    if ($s === '') return null;
    $s = str_replace(',', '.', $s);
    $s = preg_replace('/[^0-9.]/', '', $s) ?? '';
    if ($s === '' || $s === '.') return null;
    return (float)$s;
}

// ----------------- dir checks -----------------
if (!is_dir($dirGdt)) @mkdir($dirGdt, 0775, true);
if ((!is_dir($dirGdt) || !is_writable($dirGdt)) && $_SERVER['REQUEST_METHOD'] === 'POST') {
    json_out(500, ['status'=>'error','message'=>'Zielverzeichnis existiert nicht oder ist nicht beschreibbar','dir'=>$dirGdt]);
}

// ----------------- request gdt -----------------
$requestPath = rtrim($dirGdt, '/') . '/' . $REQUEST_GDT_NAME;
$hasRequest  = is_file($requestPath);
$reqFields   = $hasRequest ? parse_gdt($requestPath) : [];

$vorname  = $reqFields['3102'] ?? '';
$nachname = $reqFields['3101'] ?? '';
$gebdat   = format_gebdat($reqFields['3103'] ?? '');

$displayName = trim(trim($vorname . ' ' . $nachname));
if ($displayName === '') $displayName = '—';

// existing contacts from request
$reqEmail   = $reqFields['3619'] ?? '';
$reqPhone1  = $reqFields['3626'] ?? '';
$reqPhone2  = $reqFields['3618'] ?? '';

// Patient ID mandatory
$patId3000 = $reqFields['3000'] ?? '';
$kennfeld  = $reqFields['8402'] ?? 'ALLG0';
if ($kennfeld === '') $kennfeld = 'ALLG0';

// sender/receiver swap
$req8315   = $reqFields['8315'] ?? '';
$req8316   = $reqFields['8316'] ?? '';
$ans8315 = ($req8316 !== '') ? $req8316 : $DEFAULT_8315;
$ans8316 = ($req8315 !== '') ? $req8315 : $DEFAULT_8316;

// ----------------- POST -----------------
if ($_SERVER['REQUEST_METHOD'] === 'POST') {

    if (!$hasRequest) json_out(409, ['status'=>'error','message'=>'Keine Auftrags-GDT gefunden ('.$REQUEST_GDT_NAME.').']);
    if ($patId3000 === '') json_out(422, ['status'=>'error','message'=>'Feld 3000 (Patienten-ID) fehlt in der Auftrags-GDT']);

    if (($_POST['action'] ?? '') === 'abort') {
        $deleted = @unlink($requestPath);
        json_out(200, ['status'=>'ok','message'=>'abgebrochen','request_deleted'=>$deleted,'request_gdt'=>$REQUEST_GDT_NAME]);
    }

    $yaml = yaml_load_or_die($YAML_PATH);
    if (isset($yaml['__error'])) json_out(500, ['status'=>'error','message'=>$yaml['__error'],'yaml'=>$YAML_PATH]);

    // hardcoded top fields
    $height = clean_utf8_text((string)($_POST['height_cm'] ?? ''), 10);
    $weight = clean_utf8_text((string)($_POST['weight_kg'] ?? ''), 10);

    $phone1 = clean_utf8_text((string)($_POST['phone1'] ?? ''), 70); // 3626
    $phone2 = clean_utf8_text((string)($_POST['phone2'] ?? ''), 70); // 3618
    $email  = clean_utf8_text((string)($_POST['email']  ?? ''), 70); // 3619

    // parse YAML-driven answers
    $rawQ = $_POST['q'] ?? [];
    if (!is_array($rawQ)) $rawQ = [];

    $answers = [];
    $sections = $yaml['sections'] ?? [];
    if (!is_array($sections)) $sections = [];

    foreach ($sections as $sec) {
        if (!is_array($sec)) continue;
        $secType = (string)($sec['type'] ?? '');
        $questions = $sec['questions'] ?? [];
        if (!is_array($questions)) continue;

        if ($secType === 'checklist') {
            foreach ($questions as $q) {
                if (!is_array($q)) continue;
                $id = (string)($q['id'] ?? '');
                if ($id === '') continue;
                $answers[$id] = !empty($rawQ[$id]);
            }
            continue;
        }

        foreach ($questions as $q) {
            if (!is_array($q)) continue;
            $id = (string)($q['id'] ?? '');
            $type = (string)($q['type'] ?? '');
            if ($id === '') continue;

            if ($type === 'multiselect') {
                $v = $rawQ[$id] ?? [];
                if (!is_array($v)) $v = [];
                $answers[$id] = array_values(array_filter(array_map(fn($x) => clean_utf8_text((string)$x, 200), $v), fn($x) => $x !== ''));
                continue;
            }

            if ($type === 'yesno') {
                // WICHTIG: als "yes"/"no" speichern (kompatibel zu YAML show_if)
                $v = (string)($rawQ[$id] ?? '');
                $answers[$id] = ($v === 'yes') ? 'yes' : 'no';
                continue;
            }

            if ($type === 'derived') {
                // ignored in input
                continue;
            }

            $answers[$id] = clean_utf8_text((string)($rawQ[$id] ?? ''), 600);
        }
    }

    // derive packyears: floor((cigs/day / 20) * years), but min 1 if any >0
    $isSmoker = (($answers['raucher'] ?? 'no') === 'yes');
    $cigs = parse_float_de((string)($answers['rauchen_zigaretten_tag'] ?? ''));
    $yrs  = parse_float_de((string)($answers['rauchen_jahre'] ?? ''));

    if ($isSmoker && $cigs !== null && $yrs !== null && $cigs > 0 && $yrs > 0) {
        $py = ($cigs / 20.0) * $yrs;
        $pyInt = (int)floor($py);
        if ($pyInt < 1 && $py > 0) $pyInt = 1;
        $answers['_packyears_text'] = 'mind. ' . $pyInt . ' Packyears';
    } else {
        $answers['_packyears_text'] = '';
    }

    // Build 6228 lines: contact updates first if changed
    $lines6228 = [];

    $chgBullets = [];
    if (norm_contact($phone1) !== '' && norm_contact($phone1) !== norm_contact($reqPhone1)) $chgBullets[] = 'Telefon 1: ' . $phone1;
    if (norm_contact($phone2) !== '' && norm_contact($phone2) !== norm_contact($reqPhone2)) $chgBullets[] = 'Telefon 2: ' . $phone2;
    if (norm_contact($email)  !== '' && norm_contact($email)  !== norm_contact($reqEmail))  $chgBullets[] = 'E-Mail: ' . $email;

    if (count($chgBullets) > 0) {
        $lines6228 = array_merge($lines6228, build_section_block_lines('Aktualisierte Kontaktinformationen', $chgBullets, $MAX_6228_BYTES));
    }

    $lines6228 = array_merge($lines6228, build_6228_blocks($yaml, $answers, $MAX_6228_BYTES));

    // Compose answer GDT 6310
    $lines = [];
    $lines[] = gdt_line('8000', '6310');
    $lines[] = gdt_line('8100', '000000');
    $lines[] = gdt_line('8315', $ans8315);
    $lines[] = gdt_line('8316', $ans8316);
    $lines[] = gdt_line('9206', '2');
    $lines[] = gdt_line('9218', '02.10');

    $lines[] = gdt_line('3000', $patId3000);
    if ($nachname !== '') $lines[] = gdt_line('3101', $nachname);
    if ($vorname  !== '') $lines[] = gdt_line('3102', $vorname);
    $raw3103 = $reqFields['3103'] ?? '';
    if ($raw3103 !== '') $lines[] = gdt_line('3103', $raw3103);

    $lines[] = gdt_line('8402', $kennfeld);

    if ($height !== '') $lines[] = gdt_line('3622', $height);
    if ($weight !== '') $lines[] = gdt_line('3623', $weight);
    if ($phone1 !== '') $lines[] = gdt_line('3626', $phone1);
    if ($phone2 !== '') $lines[] = gdt_line('3618', $phone2);
    if ($email  !== '') $lines[] = gdt_line('3619', $email);

    $lines[] = gdt_line('6200', $ANSWER_6200);
    $lines[] = gdt_line('6201', $ANSWER_6201);

    foreach ($lines6228 as $l) $lines[] = $l;

    $lines[] = gdt_line('9999', '');

    $outGdtPath = rtrim($dirGdt, '/') . '/' . $OUT_GDT_NAME;
    write_gdt_file($outGdtPath, $lines);

    $deleted = @unlink($requestPath);

    json_out(200, [
        'status'          => 'ok',
        'message'         => 'Anamnese übermittelt',
        'answer_gdt'      => $OUT_GDT_NAME,
        'request_gdt'     => $REQUEST_GDT_NAME,
        'request_deleted' => $deleted,
        'contact_changed' => (count($chgBullets) > 0),
        'packyears'       => (string)($answers['_packyears_text'] ?? ''),
    ]);
}

// ----------------- GET -----------------
$scriptName = $_SERVER['SCRIPT_NAME'] ?? '';
?>
<?php if (!is_file($requestPath)) { ?>
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <meta http-equiv="refresh" content="3" />
  <title><?php echo h($UI_TITLE); ?></title>
  <style>
    :root { --maxw: 520px; }
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background:#f2f2f7; margin:0; padding:20px; text-align:center; }
    .card { background:#fff; border-radius:14px; padding:16px; box-shadow:0 6px 18px rgba(0,0,0,0.06); margin:0 auto; max-width:var(--maxw); }
    .patient { font-size: 2.3rem; font-weight: 900; margin: 4px 0 10px 0; }
    .hint { font-size:1rem; color:#555; line-height:1.4; }
    .small { font-size:0.85rem; color:#777; margin-top:10px; }
    .footer { margin-top: 14px; font-size: 0.8rem; color: #777; }
  </style>
</head>
<body>
  <div class="card">
    <div class="patient"><?php echo h($displayName); ?></div>
    <div class="hint">
      Warte auf Auftrags-GDT im Ordner:<br/>
      <b><?php echo h($dirGdt); ?></b><br/><br/>
      Erwarteter Dateiname:<br/>
      <b><?php echo h($REQUEST_GDT_NAME); ?></b><br/><br/>
      Seite aktualisiert sich automatisch alle 3 Sekunden.
    </div>
    <div class="small">Sobald die Auftragsdatei da ist,<br>erscheint der Anamnese-Bogen.</div>
    <div class="footer"><?php echo h($APP_FOOTER . ' · ' . $APP_VERSION); ?></div>
  </div>
</body>
</html>
<?php exit; } ?>

<?php
$yaml = yaml_load_or_die($YAML_PATH);
$yamlError = $yaml['__error'] ?? '';
$sections = (isset($yaml['sections']) && is_array($yaml['sections'])) ? $yaml['sections'] : [];
?>
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <meta name="apple-mobile-web-app-capable" content="yes" />
  <meta name="apple-mobile-web-app-status-bar-style" content="default" />
  <meta name="apple-mobile-web-app-title" content="<?php echo h($UI_TITLE); ?>" />
  <title><?php echo h($UI_TITLE); ?></title>

  <style>
    :root { --maxw: 780px; }
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background:#f2f2f7; margin:0; padding:20px; }
    .card { background:#fff; border-radius:14px; padding:16px; box-shadow:0 6px 18px rgba(0,0,0,0.06); margin:0 auto; max-width:var(--maxw); }
    .patient { font-size: 2.0rem; font-weight: 900; margin: 0 0 6px 0; }
    .sub { color:#444; margin:0 0 12px 0; line-height:1.35; }
    .row { display:flex; gap:10px; flex-wrap:wrap; }
    .field { flex:1 1 220px; text-align:left; margin: 8px 0; }
    label { display:block; font-size:0.95rem; font-weight:700; margin-bottom:6px; color:#222; }
    input, textarea { width:100%; box-sizing:border-box; padding:10px 12px; border-radius:10px; border:1px solid #ddd; font-size:1rem; }
    textarea { min-height: 88px; resize: vertical; }

    .section { margin-top: 16px; padding-top: 8px; border-top: 1px solid #eee; }
    .section h2 { font-size: 1.2rem; margin: 10px 0 6px 0; }

    .checkgrid { display:grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap:10px; }
    .check { display:flex; align-items:center; gap:10px; background:#fafafa; border:1px solid #eee; border-radius:12px; padding:10px 12px; }
    .check input { width:22px; height:22px; flex:0 0 auto; }
    .check span { font-size:1.05rem; overflow-wrap:anywhere; }

    .radioRow{
      display:grid;
      grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
      gap:10px;
    }
    .radioPill{
      display:flex;
      align-items:center;
      justify-content:center;
      gap:10px;
      background:#fafafa;
      border:1px solid #eee;
      border-radius:12px;
      padding:12px 12px;
      min-height:44px;
      box-sizing:border-box;
    }
    .radioPill input{ width:22px; height:22px; flex:0 0 auto; }
    .radioPill span{ white-space:normal; overflow-wrap:anywhere; text-align:center; }

    button { font-size: 1.05rem; padding: 14px 18px; border-radius: 12px; border: none; width: 100%; margin: 10px 0; cursor: pointer; }
    #submitBtn { background: #34c759; color:#fff; }
    #abortBtn { background: #ff3b30; color:#fff; }
    #submitBtn:disabled { background: #a7e3b7; cursor: not-allowed; }

    #status { font-size: 1.05rem; font-weight: 700; color: #333; margin-top: 10px; min-height: 1.4em; word-break: break-word; }
    .footer { margin-top: 14px; font-size: 0.8rem; color: #777; text-align:center; }
    .warn { background:#fff7e6; border:1px solid #ffe0a6; padding:12px; border-radius:12px; margin:10px 0; color:#6b4b00; }

    .hidden { display:none !important; }
  </style>
</head>
<body>
  <div class="card">

    <div class="patient"><?php echo h($displayName); ?></div>
    <div class="sub">
      Geburtsdatum: <b><?php echo h($gebdat !== '' ? $gebdat : '—'); ?></b>
    </div>

    <?php if ($yamlError !== '') { ?>
      <div class="warn">
        <b>⚠️ YAML-Fehler:</b> <?php echo h($yamlError); ?><br/>
        Datei: <code><?php echo h($YAML_PATH); ?></code>
      </div>
    <?php } ?>

    <form id="anamForm">

      <div class="section">
        <h2>Körpermaße & Kontakt</h2>
        <div class="row">
          <div class="field">
            <label for="height_cm">Körpergröße (cm)</label>
            <input id="height_cm" name="height_cm" inputmode="numeric" placeholder="z. B. 180" />
          </div>
          <div class="field">
            <label for="weight_kg">Körpergewicht (kg)</label>
            <input id="weight_kg" name="weight_kg" inputmode="decimal" placeholder="z. B. 82,5" />
          </div>
        </div>

        <div class="row">
          <div class="field">
            <label for="phone1">Telefon 1</label>
            <input id="phone1" name="phone1" inputmode="tel" value="<?php echo h($reqPhone1); ?>" />
          </div>
          <div class="field">
            <label for="phone2">Telefon 2</label>
            <input id="phone2" name="phone2" inputmode="tel" value="<?php echo h($reqPhone2); ?>" />
          </div>
          <div class="field">
            <label for="email">E-Mail</label>
            <input id="email" name="email" inputmode="email" value="<?php echo h($reqEmail); ?>" />
          </div>
        </div>
      </div>

      <?php foreach ($sections as $secIdx => $sec) {
        if (!is_array($sec)) continue;
        $title = (string)($sec['title'] ?? '');
        if ($title === '') continue;
        $type  = (string)($sec['type'] ?? '');
        $questions = $sec['questions'] ?? [];
        if (!is_array($questions)) $questions = [];

        $secShow = $sec['show_if'] ?? null;
        $secAttr = '';
        if (is_array($secShow) && isset($secShow['id'])) {
            $secAttr = ' data-show-id="' . h((string)$secShow['id']) . '"';
            if (array_key_exists('equals', $secShow)) {
                $secAttr .= ' data-show-op="equals" data-show-val="' . h((string)$secShow['equals']) . '"';
            } elseif (array_key_exists('not_equals', $secShow)) {
                $secAttr .= ' data-show-op="not_equals" data-show-val="' . h((string)$secShow['not_equals']) . '"';
            }
        }
      ?>
        <div class="section" data-section="<?php echo h((string)$secIdx); ?>"<?php echo $secAttr; ?>>
          <h2><?php echo h($title); ?></h2>

          <?php if ($type === 'checklist') { ?>
            <div class="checkgrid">
              <?php foreach ($questions as $q) {
                if (!is_array($q)) continue;
                $id = (string)($q['id'] ?? '');
                $label = (string)($q['label'] ?? '');
                if ($id === '' || $label === '') continue;
              ?>
                <label class="check" data-qwrap="1" data-qid="<?php echo h($id); ?>">
                  <input type="checkbox" name="q[<?php echo h($id); ?>]" value="1" />
                  <span><?php echo h($label); ?></span>
                </label>
              <?php } ?>
            </div>
          <?php } else { ?>
            <?php foreach ($questions as $q) {
              if (!is_array($q)) continue;
              $id = (string)($q['id'] ?? '');
              $label = (string)($q['label'] ?? '');
              $qType = (string)($q['type'] ?? '');
              $opts = $q['options'] ?? [];
              if ($id === '' || $label === '') continue;

              $show = $q['show_if'] ?? null;
              $wrapAttr = '';
              if (is_array($show) && isset($show['id'])) {
                  $wrapAttr = ' data-show-id="' . h((string)$show['id']) . '"';
                  if (array_key_exists('equals', $show)) {
                      $wrapAttr .= ' data-show-op="equals" data-show-val="' . h((string)$show['equals']) . '"';
                  } elseif (array_key_exists('not_equals', $show)) {
                      $wrapAttr .= ' data-show-op="not_equals" data-show-val="' . h((string)$show['not_equals']) . '"';
                  }
              }

              if ($qType === 'derived') {
                  echo '<div class="field hidden" data-qwrap="1" data-qid="'.h($id).'"'.$wrapAttr.'></div>';
                  continue;
              }
            ?>
              <div class="field" data-qwrap="1" data-qid="<?php echo h($id); ?>"<?php echo $wrapAttr; ?>>

              <?php if ($qType === 'yesno') { ?>
                  <label><?php echo h($label); ?></label>
                  <div class="radioRow">
                    <label class="radioPill">
                      <input type="radio" name="q[<?php echo h($id); ?>]" value="yes" />
                      <span>Ja</span>
                    </label>
                    <label class="radioPill">
                      <input type="radio" name="q[<?php echo h($id); ?>]" value="no" checked />
                      <span>Nein</span>
                    </label>
                  </div>
              <?php } elseif ($qType === 'choice' && is_array($opts)) { ?>
                  <label><?php echo h($label); ?></label>
                  <div class="radioRow">
                    <?php
                      $default = null;
                      if (in_array('nein', $opts, true)) $default = 'nein';
                      elseif (count($opts) > 0) $default = (string)$opts[0];

                      foreach ($opts as $opt) {
                        $opt = (string)$opt;
                        if ($opt === '') continue;
                        $checked = ($opt === $default) ? 'checked' : '';
                    ?>
                      <label class="radioPill">
                        <input type="radio" name="q[<?php echo h($id); ?>]" value="<?php echo h($opt); ?>" <?php echo $checked; ?> />
                        <span><?php echo h($opt); ?></span>
                      </label>
                    <?php } ?>
                  </div>
              <?php } elseif ($qType === 'multiselect' && is_array($opts)) { ?>
                  <label><?php echo h($label); ?></label>
                  <div class="checkgrid">
                    <?php foreach ($opts as $opt) {
                      $opt = (string)$opt;
                      if ($opt === '') continue;
                    ?>
                      <label class="check">
                        <input type="checkbox" name="q[<?php echo h($id); ?>][]" value="<?php echo h($opt); ?>" />
                        <span><?php echo h($opt); ?></span>
                      </label>
                    <?php } ?>
                  </div>
              <?php } elseif ($qType === 'number') { ?>
                  <label for="<?php echo h('q_'.$id); ?>"><?php echo h($label); ?></label>
                  <input id="<?php echo h('q_'.$id); ?>" name="q[<?php echo h($id); ?>]" inputmode="numeric" />
              <?php } else { ?>
                  <label for="<?php echo h('q_'.$id); ?>"><?php echo h($label); ?></label>
                  <?php $ml = !empty($q['multiline']); ?>
                  <?php if ($ml) { ?>
                    <textarea id="<?php echo h('q_'.$id); ?>" name="q[<?php echo h($id); ?>]"></textarea>
                  <?php } else { ?>
                    <input id="<?php echo h('q_'.$id); ?>" name="q[<?php echo h($id); ?>]" />
                  <?php } ?>
              <?php } ?>

              </div>
            <?php } ?>
          <?php } ?>

        </div>
      <?php } ?>

      <button id="submitBtn" type="button">✅ Anamnese absenden</button>
      <button id="abortBtn" type="button">❌ Abbruch</button>

      <div id="status"></div>
      <div class="footer"><?php echo h($APP_FOOTER . ' · ' . $APP_VERSION); ?></div>
    </form>
  </div>

  <script>
    var SCRIPT_NAME = <?php echo json_encode($scriptName, JSON_UNESCAPED_SLASHES); ?>;

    var POST_URL;
    try { POST_URL = new URL(SCRIPT_NAME, window.location.href).toString(); }
    catch (e) { POST_URL = window.location.origin + window.location.pathname; }

    var submitBtn = document.getElementById("submitBtn");
    var abortBtn  = document.getElementById("abortBtn");
    var statusEl  = document.getElementById("status");
    var formEl    = document.getElementById("anamForm");

    function setStatus(msg, isError) {
      statusEl.textContent = msg || "";
      statusEl.style.color = isError ? "#d00" : "#333";
    }

    function getAnswerValue(qid) {
      var cb = formEl.querySelector('input[type="checkbox"][name="q['+CSS.escape(qid)+']"]');
      if (cb) return cb.checked ? true : false;

      var cbs = formEl.querySelectorAll('input[type="checkbox"][name="q['+CSS.escape(qid)+'][]"]');
      if (cbs && cbs.length) {
        var any = false;
        cbs.forEach(function(x){ if (x.checked) any = true; });
        return any ? "selected" : "";
      }

      var r = formEl.querySelector('input[type="radio"][name="q['+CSS.escape(qid)+']"]:checked');
      if (r) return r.value;

      var t = formEl.querySelector('[name="q['+CSS.escape(qid)+']"]');
      if (t) return (t.value || "");
      return "";
    }

    function applyShowIf() {
      var nodes = formEl.querySelectorAll('[data-qwrap="1"][data-show-id]');
      nodes.forEach(function(el){
        var depId = el.getAttribute('data-show-id');
        var op = el.getAttribute('data-show-op') || 'equals';
        var val = el.getAttribute('data-show-val');

        var cur = getAnswerValue(depId);
        var show = true;

        if (op === 'equals') show = (String(cur) === String(val));
        else if (op === 'not_equals') show = (String(cur) !== String(val));

        el.classList.toggle('hidden', !show);
      });

      var secs = formEl.querySelectorAll('.section[data-show-id]');
      secs.forEach(function(el){
        var depId = el.getAttribute('data-show-id');
        var op = el.getAttribute('data-show-op') || 'equals';
        var val = el.getAttribute('data-show-val');

        var cur = getAnswerValue(depId);
        var show = true;

        if (op === 'equals') show = (String(cur) === String(val));
        else if (op === 'not_equals') show = (String(cur) !== String(val));

        el.classList.toggle('hidden', !show);
      });
    }

    formEl.addEventListener('change', applyShowIf);
    formEl.addEventListener('input', applyShowIf);
    applyShowIf();

    submitBtn.addEventListener("click", function () {
      submitBtn.disabled = true;
      abortBtn.disabled = true;
      setStatus("Übermittlung läuft…", false);

      var formData = new FormData(formEl);

      fetch(POST_URL, { method: "POST", body: formData })
        .then(function(res) {
          var ct = res.headers.get("content-type") || "";
          if (ct.indexOf("application/json") !== -1) {
            return res.json().then(function(data) { return { ok: res.ok, data: data }; });
          }
          return res.text().then(function(text) {
            throw new Error("Server hat kein JSON geliefert: " + text.slice(0, 200));
          });
        })
        .then(function(r) {
          if (!r.ok || !r.data || r.data.status !== "ok") {
            var msg = (r.data && r.data.message) ? r.data.message : "Übermittlung fehlgeschlagen";
            throw new Error(msg);
          }
          setStatus("✅ erfolgreich übermittelt", false);
          setTimeout(function() { location.reload(); }, 1000);
        })
        .catch(function(err) {
          setStatus("❌ " + (err && err.message ? err.message : String(err)), true);
          submitBtn.disabled = false;
          abortBtn.disabled = false;
        });
    });

    abortBtn.addEventListener("click", function () {
      if (!confirm("Vorgang wirklich abbrechen? Die Anforderung wird gelöscht.")) return;

      submitBtn.disabled = true;
      abortBtn.disabled = true;
      setStatus("Abbruch läuft…", false);

      var formData = new FormData();
      formData.append("action", "abort");

      fetch(POST_URL, { method: "POST", body: formData })
        .then(function(res) {
          var ct = res.headers.get("content-type") || "";
          if (ct.indexOf("application/json") !== -1) return res.json();
          return res.text().then(function(text) {
            throw new Error("Server hat kein JSON geliefert: " + text.slice(0, 200));
          });
        })
        .then(function(data) {
          if (!data || data.status !== "ok") throw new Error((data && data.message) ? data.message : "Abbruch fehlgeschlagen");
          setStatus("❌ abgebrochen", false);
          setTimeout(function() { location.reload(); }, 800);
        })
        .catch(function(err) {
          setStatus("❌ " + (err && err.message ? err.message : String(err)), true);
          submitBtn.disabled = false;
          abortBtn.disabled = false;
        });
    });
  </script>
</body>
</html>
