<?php
declare(strict_types=1);

/*
 * befund.php v1.7
 *
 * Changelog (since v1.0)
 * - v1.0: Übernahme aus selfie.php (Grundworkflow): Auftrags-GDT finden, Foto-Upload speichern, Antwort-GDT 6310 schreiben, Auftrags-GDT löschen
 * - v1.1: Standard Rückkamera (capture=environment)
 *         + KEIN Resize: JPEG wird 1:1 hochgeladen; Nicht-JPEG wird ohne Resize nach JPEG gewandelt (hohe Qualität)
 *         + Mehrere Bilder pro Auftrag: Thumbnail-Liste mit Löschen, Button "weiteres Bild"
 *         + Server speichert Dateien als ######_01.jpg, ######_02.jpg, ... (6-stellige Zufallsbasis pro Upload)
 *         + Fix iOS/Safari/WebApp: absolute Upload-URL
 * - v1.2: Auftragsdatei ist fest: BEFT2MD.gdt
 * - v1.3: Default Sender/Empfänger-ID angepasst: BIMP_GDT
 * - v1.4: Anhang-Text wieder wie früher über 6304 pro Anhang ("Anhang n zur Befund-Messung.JPG")
 * - v1.5: Fix: Multi-Upload wieder korrekt (FormData: images[]), dadurch mehrere Anhänge werden übernommen
 *         + Entfernt alle "Selfie"-Reste aus Texten/Labels
 * - v1.6: Fix iOS-Fehler "The string did not match the expected pattern." (CP437-Bytes nicht mehr im JSON)
 * - v1.7: UI: Patientenname wieder ganz oben sehr groß (wie früher)
 *         + Label geändert: "Notiz:" statt "Freitext: (...)"
 */

$APP_FOOTER  = 'fragebogenpi von Dr. Thomas Kienzle 2026';
$APP_VERSION = 'v1.7 (befund.php)';

$dirGdt = '/srv/fragebogenpi/GDT';     // Zielordner (GDT + Bilder)

// Auftragsdatei (Request) ist fest:
$REQUEST_GDT_NAME = 'BEFT2MD.gdt';

// Antwortdatei:
$OUT_GDT_NAME = 'T2MDBEF.gdt';

// Default IDs falls 8315/8316 in der Request fehlen:
$DEFAULT_8315 = 'T2MED_PX';
$DEFAULT_8316 = 'BIMP_GDT';

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
    $len  = 3 + strlen($rest); // ohne Zeilenumbruch
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

function to_cp437_safe(string $s, int $maxLen = 70): string {
    $s = str_replace(["\r", "\n", "\t"], ' ', $s);
    $s = preg_replace('/\s+/', ' ', $s) ?? $s;
    $s = trim($s);

    if (function_exists('mb_substr')) {
        $s = mb_substr($s, 0, 200, 'UTF-8');
    }

    if (function_exists('iconv')) {
        $conv = @iconv('UTF-8', 'CP437//TRANSLIT//IGNORE', $s);
        if ($conv !== false && $conv !== '') {
            $s = $conv; // CP437-Bytes
        } else {
            $s = preg_replace('/[^\x20-\x7E]/', '?', $s) ?? $s;
        }
    } else {
        $s = preg_replace('/[^\x20-\x7E]/', '?', $s) ?? $s;
    }

    if (strlen($s) > $maxLen) $s = substr($s, 0, $maxLen);
    return $s;
}

function generate_unique_base(string $dir, int $tries = 50): string {
    $dir = rtrim($dir, '/');
    for ($i=0; $i<$tries; $i++) {
        $base = str_pad((string)random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        $collision = false;
        for ($j=1; $j<=5; $j++) {
            $name = sprintf('%s_%02d.jpg', $base, $j);
            if (is_file($dir . '/' . $name)) { $collision = true; break; }
        }
        if (!$collision) return $base;
    }
    return str_pad((string)random_int(0, 999999), 6, '0', STR_PAD_LEFT);
}

function make_attachment_title(int $n): string {
    return 'Anhang ' . $n . ' zur Befund-Messung.JPG';
}

// ----------------- dir checks -----------------
if (!is_dir($dirGdt)) {
    @mkdir($dirGdt, 0775, true);
}
if ((!is_dir($dirGdt) || !is_writable($dirGdt)) && $_SERVER['REQUEST_METHOD'] === 'POST') {
    json_out(500, [
        'status'  => 'error',
        'message' => 'Zielverzeichnis existiert nicht oder ist nicht beschreibbar',
        'dir'     => $dirGdt
    ]);
}

// ----------------- request gdt (fixed name) -----------------
$requestPath = rtrim($dirGdt, '/') . '/' . $REQUEST_GDT_NAME;
$hasRequest  = is_file($requestPath);
$reqFields   = $hasRequest ? parse_gdt($requestPath) : [];

$vorname  = $reqFields['3102'] ?? '';
$nachname = $reqFields['3101'] ?? '';
$displayName = trim($vorname . ' ' . $nachname);
if ($displayName === '') $displayName = '—';

// ----------------- POST -----------------
if ($_SERVER['REQUEST_METHOD'] === 'POST') {

    $debugBase = [
        'content_type'   => $_SERVER['CONTENT_TYPE']   ?? null,
        'content_length' => $_SERVER['CONTENT_LENGTH'] ?? null,
        'post_keys'      => array_keys($_POST),
        'files_keys'     => array_keys($_FILES),
        'dir'            => $dirGdt,
        'request_gdt'    => $hasRequest ? $REQUEST_GDT_NAME : null,
    ];

    if (($_POST['action'] ?? '') === 'abort') {
        if ($hasRequest) {
            $ok = @unlink($requestPath);
            json_out(200, [
                'status'  => 'ok',
                'message' => 'abgebrochen',
                'request_deleted' => $ok,
                'request_gdt' => $REQUEST_GDT_NAME,
            ]);
        }
        json_out(200, [
            'status'  => 'ok',
            'message' => 'keine Anforderungsdatei vorhanden'
        ]);
    }

    if (!$hasRequest) {
        json_out(409, [
            'status'  => 'error',
            'message' => 'Keine Auftrags-GDT gefunden (BEFT2MD.gdt).',
            'debug'   => $debugBase
        ]);
    }

    $cl = (int)($_SERVER['CONTENT_LENGTH'] ?? 0);
    if (empty($_FILES)) {
        json_out(400, [
            'status'  => 'error',
            'message' => 'Keine Dateien empfangen. Häufige Ursache: Upload zu groß (post_max_size / upload_max_filesize).',
            'content_length' => $cl,
            'php_limits' => [
                'post_max_size'       => ini_get('post_max_size'),
                'upload_max_filesize' => ini_get('upload_max_filesize'),
                'max_file_uploads'    => ini_get('max_file_uploads'),
            ],
            'debug'   => $debugBase
        ]);
    }

    $images = $_FILES['images'] ?? null;
    if ($images === null) {
        json_out(400, [
            'status'  => 'error',
            'message' => '$_FILES["images"] fehlt',
            'files_keys' => array_keys($_FILES),
            'debug'   => $debugBase
        ]);
    }

    if (!is_array($images['name'])) {
        $images = [
            'name'     => [$images['name']],
            'type'     => [$images['type']],
            'tmp_name' => [$images['tmp_name']],
            'error'    => [$images['error']],
            'size'     => [$images['size']],
        ];
    }

    $noteUtf8 = clean_utf8_text((string)($_POST['note'] ?? ''), 200);
    $noteCp   = to_cp437_safe($noteUtf8, 70);

    $req = $reqFields;
    $req8315   = $req['8315'] ?? '';
    $req8316   = $req['8316'] ?? '';
    $patId3000 = $req['3000'] ?? '';
    $nn        = $req['3101'] ?? '';
    $vn        = $req['3102'] ?? '';
    $kennfeld  = $req['8402'] ?? 'ALLG0';
    if ($kennfeld === '') $kennfeld = 'ALLG0';

    if ($patId3000 === '') {
        json_out(422, [
            'status'  => 'error',
            'message' => 'Feld 3000 (Patienten-ID) fehlt in der Auftrags-GDT',
            'debug'   => $debugBase
        ]);
    }

    $ans8315 = ($req8316 !== '') ? $req8316 : $DEFAULT_8315;
    $ans8316 = ($req8315 !== '') ? $req8315 : $DEFAULT_8316;

    $finfo = new finfo(FILEINFO_MIME_TYPE);
    $savedFiles = [];

    $base = generate_unique_base($dirGdt);

    $count = count($images['name']);
    $maxFiles = 30;

    if ($count < 1) {
        json_out(400, [
            'status'  => 'error',
            'message' => 'Keine Bilder empfangen',
            'debug'   => $debugBase
        ]);
    }
    if ($count > $maxFiles) {
        json_out(400, [
            'status'  => 'error',
            'message' => 'Zu viele Bilder auf einmal (Limit: '.$maxFiles.')',
            'count'   => $count,
            'debug'   => $debugBase
        ]);
    }

    for ($i = 0; $i < $count; $i++) {
        $err = $images['error'][$i] ?? UPLOAD_ERR_NO_FILE;
        if ($err !== UPLOAD_ERR_OK) {
            $errorMap = [
                UPLOAD_ERR_INI_SIZE   => 'UPLOAD_ERR_INI_SIZE (upload_max_filesize)',
                UPLOAD_ERR_FORM_SIZE  => 'UPLOAD_ERR_FORM_SIZE',
                UPLOAD_ERR_PARTIAL    => 'UPLOAD_ERR_PARTIAL',
                UPLOAD_ERR_NO_FILE    => 'UPLOAD_ERR_NO_FILE',
                UPLOAD_ERR_NO_TMP_DIR => 'UPLOAD_ERR_NO_TMP_DIR',
                UPLOAD_ERR_CANT_WRITE => 'UPLOAD_ERR_CANT_WRITE',
                UPLOAD_ERR_EXTENSION  => 'UPLOAD_ERR_EXTENSION',
            ];
            json_out(400, [
                'status'        => 'error',
                'message'       => 'Upload-Fehler bei Bild #' . ($i+1),
                'error_code'    => $err,
                'error_meaning' => $errorMap[$err] ?? 'unbekannt',
                'php_limits'    => [
                    'upload_max_filesize' => ini_get('upload_max_filesize'),
                    'post_max_size'       => ini_get('post_max_size'),
                    'max_file_uploads'    => ini_get('max_file_uploads'),
                ],
                'debug'         => $debugBase
            ]);
        }

        $tmp = $images['tmp_name'][$i] ?? '';
        if ($tmp === '' || !is_uploaded_file($tmp)) {
            json_out(400, [
                'status'  => 'error',
                'message' => 'tmp_name ist kein gültiger Upload bei Bild #' . ($i+1),
                'tmp'     => $tmp,
                'debug'   => $debugBase
            ]);
        }

        $mime  = $finfo->file($tmp);
        if ($mime !== 'image/jpeg') {
            json_out(400, [
                'status'  => 'error',
                'message' => 'Bitte JPEG senden (wird im Browser automatisch erzeugt).',
                'mime'    => $mime,
                'debug'   => $debugBase
            ]);
        }

        $seq = $i + 1;
        $outName = sprintf('%s_%02d.jpg', $base, $seq);
        $target  = rtrim($dirGdt, '/') . '/' . $outName;

        if (!move_uploaded_file($tmp, $target)) {
            json_out(500, [
                'status'  => 'error',
                'message' => 'move_uploaded_file fehlgeschlagen bei Bild #' . ($i+1),
                'target'  => $target,
                'debug'   => $debugBase
            ]);
        }

        $savedFiles[] = $outName;
    }

    $lines = [];
    $lines[] = gdt_line('8000', '6310');
    $lines[] = gdt_line('8100', '000000');
    $lines[] = gdt_line('8315', $ans8315);
    $lines[] = gdt_line('8316', $ans8316);
    $lines[] = gdt_line('9206', '2');
    $lines[] = gdt_line('9218', '02.10');

    $lines[] = gdt_line('3000', $patId3000);
    if ($nn !== '') $lines[] = gdt_line('3101', $nn);
    if ($vn !== '') $lines[] = gdt_line('3102', $vn);
    $lines[] = gdt_line('8402', $kennfeld);

    $lines[] = gdt_line('6200', 'KI01');
    $lines[] = gdt_line('6201', 'KI-Befundfoto');

    if ($noteCp !== '') {
        $lines[] = gdt_line('6228', 'Notiz: ' . $noteCp);
    }

    foreach ($savedFiles as $idx => $fname) {
        $n = $idx + 1;
        $lines[] = gdt_line('6302', str_pad((string)$n, 6, '0', STR_PAD_LEFT));
        $lines[] = gdt_line('6303', 'JPG');
        $lines[] = gdt_line('6304', make_attachment_title($n));
        $lines[] = gdt_line('6305', $fname);
    }

    $lines[] = gdt_line('9999', '');

    $outGdtPath = rtrim($dirGdt, '/') . '/' . $OUT_GDT_NAME;
    write_gdt_file($outGdtPath, $lines);

    $deleted = @unlink($requestPath);

    json_out(200, [
        'status'          => 'ok',
        'message'         => 'erfolgreich übermittelt',
        'files'           => $savedFiles,
        'answer_gdt'      => $OUT_GDT_NAME,
        'request_gdt'     => $REQUEST_GDT_NAME,
        'request_deleted' => $deleted,
        'note_written'    => ($noteUtf8 !== ''),
        'note'            => $noteUtf8,
        'ids'             => ['8315' => $ans8315, '8316' => $ans8316],
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
  <title>Befund Upload</title>
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
    <div class="small">Sobald die Auftragsdatei da ist,<br>erscheint der Kamera-Button.</div>
    <div class="footer"><?php echo h($APP_FOOTER . ' · ' . $APP_VERSION); ?></div>
  </div>
</body>
</html>
<?php exit; } ?>

<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <meta name="apple-mobile-web-app-capable" content="yes" />
  <meta name="apple-mobile-web-app-status-bar-style" content="default" />
  <meta name="apple-mobile-web-app-title" content="Befund Upload" />
  <title>Befund Upload</title>

  <style>
    :root { --maxw: 420px; }
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background:#f2f2f7; margin:0; padding:20px; text-align:center; }
    .card { background:#fff; border-radius:14px; padding:16px; box-shadow:0 6px 18px rgba(0,0,0,0.06); margin:0 auto; max-width:var(--maxw); }

    .patient {
      font-size: 2.2rem;
      font-weight: 900;
      letter-spacing: 0.2px;
      margin: 0 0 10px 0;
    }

    h1 { font-size: 1.2rem; margin: 0 0 10px 0; }

    button { font-size: 1.05rem; padding: 14px 18px; border-radius: 12px; border: none; width: 100%; margin: 10px 0; cursor: pointer; }
    #takePhotoBtn { background: #007aff; color:#fff; }
    #moreBtn { background: #007aff; color:#fff; display:none; }
    #uploadBtn { background: #34c759; color:#fff; }
    #abortBtn { background: #ff3b30; color:#fff; }
    #uploadBtn:disabled { background: #a7e3b7; cursor: not-allowed; }

    #status { font-size: 1.05rem; font-weight: 700; color: #333; margin-top: 12px; min-height: 1.4em; word-break: break-word; }

    .thumbs { margin-top: 12px; display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; }
    .thumb { position: relative; border-radius: 12px; overflow: hidden; background: #f4f4f6; border: 1px solid #eee; aspect-ratio: 1 / 1; }
    .thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
    .del { position: absolute; right: 6px; top: 6px; border: none; border-radius: 10px; padding: 6px 8px; font-size: 0.9rem; background: rgba(0,0,0,0.55); color: #fff; cursor: pointer; }

    .footer { margin-top: 14px; font-size: 0.8rem; color: #777; }

    .noteWrap { text-align:left; margin: 10px 0 12px 0; }
    .noteWrap label { display:block; font-size:0.95rem; font-weight:700; margin-bottom:6px; color:#222; }
    .noteWrap input { width:100%; box-sizing:border-box; padding:10px 12px; border-radius:10px; border:1px solid #ddd; font-size:1rem; }
  </style>
</head>
<body>
  <div class="card">

    <div class="patient"><?php echo h($displayName); ?></div>

    <h1>Dokument/Befund fotografieren & hochladen</h1>

    <input id="cameraInput" type="file" accept="image/*" capture="environment" style="display:none" />

    <div class="noteWrap">
      <label for="note">Notiz:</label>
      <input id="note" type="text" placeholder="z. B. ‚Üble Wunde‘" />
    </div>

    <button id="takePhotoBtn">📷 1. Bild aufnehmen</button>
    <button id="moreBtn">➕ Weiteres Bild aufnehmen</button>

    <button id="uploadBtn" disabled>⬆️ Upload</button>
    <button id="abortBtn">❌ Abbruch</button>

    <div id="thumbs" class="thumbs" aria-label="Vorschau"></div>
    <div id="status"></div>

    <div class="footer"><?php echo h($APP_FOOTER . ' · ' . $APP_VERSION); ?></div>
  </div>

  <script>
    var SCRIPT_NAME = <?php echo json_encode($scriptName, JSON_UNESCAPED_SLASHES); ?>;

    var UPLOAD_URL;
    try { UPLOAD_URL = new URL(SCRIPT_NAME, window.location.href).toString(); }
    catch (e) { UPLOAD_URL = window.location.origin + window.location.pathname; }

    var cameraInput  = document.getElementById("cameraInput");
    var takePhotoBtn = document.getElementById("takePhotoBtn");
    var moreBtn      = document.getElementById("moreBtn");
    var uploadBtn    = document.getElementById("uploadBtn");
    var abortBtn     = document.getElementById("abortBtn");
    var statusEl     = document.getElementById("status");
    var thumbsEl     = document.getElementById("thumbs");
    var noteEl       = document.getElementById("note");

    var items = [];

    function setStatus(msg, isError) {
      statusEl.textContent = msg || "";
      statusEl.style.color = isError ? "#d00" : "#333";
    }

    function updateUI() {
      var n = items.length;
      uploadBtn.disabled = (n === 0);
      moreBtn.style.display = (n > 0) ? "block" : "none";
      takePhotoBtn.textContent = (n === 0) ? "📷 1. Bild aufnehmen" : ("📷 " + (n+1) + ". Bild aufnehmen");
    }

    function renderThumbs() {
      thumbsEl.innerHTML = "";
      items.forEach(function(it, idx) {
        var wrap = document.createElement("div");
        wrap.className = "thumb";

        var img = document.createElement("img");
        img.src = it.url;
        img.alt = "Bild " + (idx+1);

        var del = document.createElement("button");
        del.className = "del";
        del.type = "button";
        del.textContent = "✕";
        del.addEventListener("click", function() {
          try { URL.revokeObjectURL(it.url); } catch(e) {}
          items.splice(idx, 1);
          renderThumbs();
          updateUI();
          setStatus(items.length ? (items.length + " Bild(er) ausgewählt") : "Kein Bild ausgewählt.", items.length === 0);
        });

        wrap.appendChild(img);
        wrap.appendChild(del);
        thumbsEl.appendChild(wrap);
      });
    }

    function triggerCamera() {
      setStatus("");
      cameraInput.value = "";
      cameraInput.click();
    }

    takePhotoBtn.addEventListener("click", triggerCamera);
    moreBtn.addEventListener("click", triggerCamera);

    function ensureJpegNoResize(file) {
      return new Promise(function(resolve, reject) {
        if (file && file.type === "image/jpeg") return resolve(file);

        var img = new Image();
        img.onload = function() {
          try {
            var w = img.naturalWidth || img.width;
            var h = img.naturalHeight || img.height;
            var canvas = document.createElement("canvas");
            canvas.width = w; canvas.height = h;
            var ctx = canvas.getContext("2d");
            ctx.drawImage(img, 0, 0, w, h);

            canvas.toBlob(function(blob) {
              if (!blob) return reject(new Error("JPEG-Konvertierung fehlgeschlagen"));
              resolve(blob);
            }, "image/jpeg", 0.95);
          } catch (e) { reject(e); }
        };
        img.onerror = function() { reject(new Error("Bild konnte nicht geladen werden")); };
        try { img.src = URL.createObjectURL(file); } catch (e) { reject(e); }
      });
    }

    cameraInput.addEventListener("change", function () {
      var file = (cameraInput.files && cameraInput.files[0]) ? cameraInput.files[0] : null;
      if (!file) { setStatus("Kein Bild ausgewählt.", true); return; }

      ensureJpegNoResize(file)
        .then(function(blobOrFile) {
          var blob = blobOrFile;
          var url  = URL.createObjectURL(blob);
          items.push({ blob: blob, url: url });
          renderThumbs();
          updateUI();
          var totalKB = Math.round(items.reduce(function(sum, it) { return sum + (it.blob.size || 0); }, 0) / 1024);
          setStatus(items.length + " Bild(er) ausgewählt (" + totalKB + " KB gesamt)", false);
        })
        .catch(function(err) {
          setStatus("❌ " + (err && err.message ? err.message : String(err)), true);
        });
    });

    uploadBtn.addEventListener("click", function () {
      if (!items.length) return;

      uploadBtn.disabled = true;
      takePhotoBtn.disabled = true;
      moreBtn.disabled = true;
      abortBtn.disabled = true;
      noteEl.disabled = true;
      setStatus("Upload läuft…", false);

      var formData = new FormData();
      formData.append("note", noteEl.value || "");

      items.forEach(function(it, idx) {
        var clientName = "image_" + String(idx+1).padStart(2, "0") + ".jpg";
        formData.append("images[]", it.blob, clientName);
      });

      fetch(UPLOAD_URL, { method: "POST", body: formData })
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
            var msg = (r.data && r.data.message) ? r.data.message : "Upload fehlgeschlagen";
            throw new Error(msg);
          }
          setStatus("✅ erfolgreich übermittelt (" + (r.data.files ? r.data.files.length : items.length) + " Datei(en))", false);
          setTimeout(function() { location.reload(); }, 1200);
        })
        .catch(function(err) {
          var msg = (err && err.message) ? err.message : String(err);
          setStatus("❌ " + msg, true);

          uploadBtn.disabled = (items.length === 0);
          takePhotoBtn.disabled = false;
          moreBtn.disabled = false;
          abortBtn.disabled = false;
          noteEl.disabled = false;
        });
    });

    abortBtn.addEventListener("click", function () {
      if (!confirm("Vorgang wirklich abbrechen? Die Anforderung wird gelöscht.")) return;

      uploadBtn.disabled = true;
      takePhotoBtn.disabled = true;
      moreBtn.disabled = true;
      abortBtn.disabled = true;
      noteEl.disabled = true;
      setStatus("Abbruch läuft…", false);

      var formData = new FormData();
      formData.append("action", "abort");

      fetch(UPLOAD_URL, { method: "POST", body: formData })
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
          var msg = (err && err.message) ? err.message : String(err);
          setStatus("❌ " + msg, true);

          uploadBtn.disabled = (items.length === 0);
          takePhotoBtn.disabled = false;
          moreBtn.disabled = false;
          abortBtn.disabled = false;
          noteEl.disabled = false;
        });
    });

    updateUI();
  </script>
</body>
</html>
