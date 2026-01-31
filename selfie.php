<?php
declare(strict_types=1);

/*
 * selfie.php v1.7
 *
 * Changelog (since v1.2)
 * - v1.2: Upload + Schreiben selfie.jpg + Antwort-GDT 6310 (6302-6305) im selben Ordner
 * - v1.3: Zielpfad fix: /srv/fragebogenpi/GDT, Suche nach Auftrags-GDT ebenfalls dort
 * - v1.4: Auto-Refresh alle 3s, wenn keine Auftrags-GDT vorhanden
 * - v1.5: Nach erfolgreicher Antwort: Auftrags-GDT löschen, UI zeigt "erfolgreich übermittelt" und lädt neu
 * - v1.6: Client-side Downscale (Canvas) statt Server-GD, da GD fehlt
 * - v1.7: UI: Patient (Vorname Nachname) ganz groß oben, entfernte Hinweis-/Endpoint-Blöcke, Abbruch-Button
 *         + Anpassungen: Downscale max. Kante 800px, Entfernt 6228 und 6304 aus Antwort-GDT, Textumbruch im Wartefenster
 */

$APP_FOOTER = 'fragebogenpi von Dr. Thomas Kienzle 2026';
$APP_VERSION = 'v1.7';

$dirPdf = '/srv/fragebogenpi/GDT';   // Zielordner (GDT)
$OUT_JPG_NAME = 'selfie.jpg';
$OUT_GDT_NAME = 'T2MDSLF.gdt';

// ----------------- helpers -----------------
function h(string $s): string { return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }

function json_out(int $code, array $payload): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
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

/**
 * Schreibt GDT mit korrekt berechnetem 8100 (6-stellige Gesamtlänge in Bytes inkl. LF).
 */
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

function find_request_gdt(string $gdtDir, string $ignoreBasename): ?string {
    $gdtDir = rtrim($gdtDir, DIRECTORY_SEPARATOR);
    $files = glob($gdtDir . DIRECTORY_SEPARATOR . '*.gdt');
    if (!$files) return null;

    $files = array_values(array_filter($files, function($p) use ($ignoreBasename) {
        return strcasecmp(basename($p), $ignoreBasename) !== 0;
    }));

    if (!$files) return null;

    usort($files, fn($a, $b) => filemtime($b) <=> filemtime($a));
    return $files[0] ?? null;
}

// ----------------- dir checks -----------------
if (!is_dir($dirPdf)) {
    @mkdir($dirPdf, 0775, true);
}
if ((!is_dir($dirPdf) || !is_writable($dirPdf)) && $_SERVER['REQUEST_METHOD'] === 'POST') {
    json_out(500, [
        'status'  => 'error',
        'message' => 'Zielverzeichnis existiert nicht oder ist nicht beschreibbar',
        'dir'     => $dirPdf
    ]);
}

// ----------------- request gdt -----------------
$requestPath = find_request_gdt($dirPdf, $OUT_GDT_NAME);
$reqFields   = ($requestPath && is_file($requestPath)) ? parse_gdt($requestPath) : [];
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
        'dir'            => $dirPdf,
        'request_gdt'    => $requestPath ? basename($requestPath) : null,
    ];

    // ---- ABBRUCH ----
    if (($_POST['action'] ?? '') === 'abort') {
        if ($requestPath && is_file($requestPath)) {
            $ok = @unlink($requestPath);
            json_out(200, [
                'status'  => 'ok',
                'message' => 'abgebrochen',
                'request_deleted' => $ok,
                'request_gdt' => basename($requestPath),
            ]);
        }
        json_out(200, [
            'status'  => 'ok',
            'message' => 'keine Anforderungsdatei vorhanden'
        ]);
    }

    if (!$requestPath || !is_file($requestPath)) {
        json_out(409, [
            'status'  => 'error',
            'message' => 'Keine Auftrags-GDT gefunden (bitte warten/refresh).',
            'debug'   => $debugBase
        ]);
    }

    if (!isset($_FILES['image'])) {
        json_out(400, [
            'status'  => 'error',
            'message' => '$_FILES["image"] fehlt',
            'debug'   => $debugBase
        ]);
    }

    $file = $_FILES['image'];

    if ($file['error'] !== UPLOAD_ERR_OK) {
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
            'status'         => 'error',
            'message'        => 'Upload-Fehler',
            'error_code'     => $file['error'],
            'error_meaning'  => $errorMap[$file['error']] ?? 'unbekannt',
            'php_limits'     => [
                'upload_max_filesize' => ini_get('upload_max_filesize'),
                'post_max_size'       => ini_get('post_max_size'),
            ],
            'debug'          => $debugBase
        ]);
    }

    if (!is_uploaded_file($file['tmp_name'])) {
        json_out(400, [
            'status'  => 'error',
            'message' => 'tmp_name ist kein gültiger Upload',
            'tmp'     => $file['tmp_name'],
            'debug'   => $debugBase
        ]);
    }

    // Wir erwarten JPEG (clientseitig erzeugt)
    $finfo = new finfo(FILEINFO_MIME_TYPE);
    $mime  = $finfo->file($file['tmp_name']);
    if ($mime !== 'image/jpeg') {
        json_out(400, [
            'status'  => 'error',
            'message' => 'Bitte JPEG senden (wird normalerweise im Browser automatisch erzeugt).',
            'mime'    => $mime,
            'debug'   => $debugBase
        ]);
    }

    $targetJpg = rtrim($dirPdf, '/') . '/' . $OUT_JPG_NAME;
    if (!move_uploaded_file($file['tmp_name'], $targetJpg)) {
        json_out(500, [
            'status'  => 'error',
            'message' => 'move_uploaded_file fehlgeschlagen',
            'target'  => $targetJpg,
            'debug'   => $debugBase
        ]);
    }

    // Requestfelder für Antwort
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

    // 8315/8316 gespiegelt (Request -> Antwort)
    $ans8315 = $req8316 !== '' ? $req8316 : 'T2MED_PX';
    $ans8316 = $req8315 !== '' ? $req8315 : 'KIMP_GDT';

    // Antwort-GDT bauen (OHNE 6228 und OHNE 6304!)
    $lines = [];
    $lines[] = gdt_line('8000', '6310');
    $lines[] = gdt_line('8100', '000000'); // placeholder
    $lines[] = gdt_line('8315', $ans8315);
    $lines[] = gdt_line('8316', $ans8316);
    $lines[] = gdt_line('9206', '2');
    $lines[] = gdt_line('9218', '02.10');

    $lines[] = gdt_line('3000', $patId3000);
    if ($nn !== '') $lines[] = gdt_line('3101', $nn);
    if ($vn !== '') $lines[] = gdt_line('3102', $vn);
    $lines[] = gdt_line('8402', $kennfeld); // ALLG0

    $lines[] = gdt_line('6200', 'KI01');
    $lines[] = gdt_line('6201', 'KI-Selfie');

    $lines[] = gdt_line('6302', '000001');
    $lines[] = gdt_line('6303', 'JPG');
    $lines[] = gdt_line('6305', $OUT_JPG_NAME);

    $lines[] = gdt_line('9999', '');

    $outGdtPath = rtrim($dirPdf, '/') . '/' . $OUT_GDT_NAME;
    write_gdt_file($outGdtPath, $lines);

    // Danach: Auftragsdatei löschen
    $deleted = @unlink($requestPath);

    json_out(200, [
        'status'          => 'ok',
        'message'         => 'erfolgreich übermittelt',
        'filename'        => $OUT_JPG_NAME,
        'mime'            => $mime,
        'path'            => $targetJpg,
        'answer_gdt'      => $OUT_GDT_NAME,
        'request_gdt'     => basename($requestPath),
        'request_deleted' => $deleted
    ]);
}

// ----------------- GET -----------------
$uploadUrl = $_SERVER['SCRIPT_NAME'];
$sessionId = $requestPath ? basename($requestPath) : 'NO_REQUEST';

?>
<?php if (!$requestPath || !is_file($requestPath)) { ?>
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <meta http-equiv="refresh" content="3" />
  <title>Selfie Upload</title>
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
      <b><?php echo h($dirPdf); ?></b><br/><br/>
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
  <meta name="apple-mobile-web-app-title" content="Selfie Upload" />
  <title>Selfie Upload</title>

  <style>
    :root { --maxw: 360px; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      background: #f2f2f7;
      margin: 0;
      padding: 20px;
      text-align: center;
    }
    .card {
      background: #fff;
      border-radius: 14px;
      padding: 16px;
      box-shadow: 0 6px 18px rgba(0,0,0,0.06);
      margin: 0 auto;
      max-width: var(--maxw);
    }
    .patient {
      font-size: 2.2rem;
      font-weight: 900;
      letter-spacing: 0.2px;
      margin: 0 0 10px 0;
    }
    h1 {
      font-size: 1.2rem;
      margin: 0 0 14px 0;
    }
    button {
      font-size: 1.05rem;
      padding: 14px 18px;
      border-radius: 12px;
      border: none;
      width: 100%;
      margin: 10px 0;
      cursor: pointer;
    }
    #takePhotoBtn { background: #007aff; color: #fff; }
    #uploadBtn { background: #34c759; color: #fff; }
    #abortBtn { background: #ff3b30; color: #fff; }
    #uploadBtn:disabled { background: #a7e3b7; cursor: not-allowed; }
    #status {
      font-size: 1.05rem;
      font-weight: 700;
      color: #333;
      margin-top: 12px;
      min-height: 1.4em;
      word-break: break-word;
    }
    #preview {
      margin-top: 12px;
      width: 100%;
      border-radius: 12px;
      display: none;
    }
    .footer { margin-top: 14px; font-size: 0.8rem; color: #777; }
  </style>
</head>
<body>
  <div class="card">
    <div class="patient"><?php echo h($displayName); ?></div>
    <h1>Selfie aufnehmen & hochladen</h1>

    <input id="cameraInput" type="file" accept="image/*" capture="user" style="display:none" />

    <button id="takePhotoBtn">📷 Selfie aufnehmen</button>
    <button id="uploadBtn" disabled>⬆️ Upload</button>
    <button id="abortBtn">❌ Abbruch</button>

    <img id="preview" alt="Vorschau" />
    <div id="status"></div>

    <div class="footer"><?php echo h($APP_FOOTER . ' · ' . $APP_VERSION); ?></div>
  </div>

  <script>
    var UPLOAD_URL = <?php echo json_encode($uploadUrl, JSON_UNESCAPED_SLASHES); ?>;
    var SESSION_ID = <?php echo json_encode($sessionId, JSON_UNESCAPED_SLASHES); ?>;

    var cameraInput = document.getElementById("cameraInput");
    var takePhotoBtn = document.getElementById("takePhotoBtn");
    var uploadBtn = document.getElementById("uploadBtn");
    var abortBtn = document.getElementById("abortBtn");
    var preview = document.getElementById("preview");
    var statusEl = document.getElementById("status");

    var selectedFile = null;

    function setStatus(msg, isError) {
      statusEl.textContent = msg || "";
      statusEl.style.color = isError ? "#d00" : "#333";
    }

    takePhotoBtn.addEventListener("click", function () {
      setStatus("");
      cameraInput.click();
    });

    cameraInput.addEventListener("change", function () {
      var file = (cameraInput.files && cameraInput.files[0]) ? cameraInput.files[0] : null;

      if (!file) {
        selectedFile = null;
        uploadBtn.disabled = true;
        preview.style.display = "none";
        setStatus("Kein Bild ausgewählt.", true);
        return;
      }

      selectedFile = file;

      try {
        preview.src = URL.createObjectURL(file);
        preview.style.display = "block";
      } catch (e) {
        preview.style.display = "none";
      }

      uploadBtn.disabled = false;

      var kb = Math.round(file.size / 1024);
      setStatus("Bild ausgewählt (" + kb + " KB)", false);
    });

    // ---- Client-side Downscale (Canvas -> JPEG) ----
    function downscaleToJpeg(file, maxDim, quality) {
      maxDim = maxDim || 800;          // max. Kante 800px
      quality = (quality == null) ? 0.82 : quality;

      return new Promise(function(resolve, reject) {
        var img = new Image();
        img.onload = function() {
          try {
            var w = img.naturalWidth || img.width;
            var h = img.naturalHeight || img.height;

            var scale = Math.min(1, maxDim / Math.max(w, h));
            var nw = Math.round(w * scale);
            var nh = Math.round(h * scale);

            var canvas = document.createElement('canvas');
            canvas.width = nw;
            canvas.height = nh;

            var ctx = canvas.getContext('2d');
            ctx.drawImage(img, 0, 0, nw, nh);

            canvas.toBlob(function(blob) {
              if (!blob) return reject(new Error("toBlob fehlgeschlagen"));
              resolve(blob);
            }, 'image/jpeg', quality);
          } catch (e) {
            reject(e);
          }
        };
        img.onerror = function() { reject(new Error("Bild konnte nicht geladen werden")); };

        try {
          img.src = URL.createObjectURL(file);
        } catch (e) {
          reject(e);
        }
      });
    }

    uploadBtn.addEventListener("click", function () {
      if (!selectedFile) return;

      uploadBtn.disabled = true;
      takePhotoBtn.disabled = true;
      abortBtn.disabled = true;
      setStatus("Upload läuft…", false);

      downscaleToJpeg(selectedFile, 800, 0.82)
        .then(function(blob) {
          var formData = new FormData();
          formData.append("image", blob, "selfie.jpg");
          formData.append("session_id", SESSION_ID);

          return fetch(UPLOAD_URL, { method: "POST", body: formData });
        })
        .then(function(res) {
          var ct = res.headers.get("content-type") || "";
          if (ct.indexOf("application/json") !== -1) {
            return res.json().then(function(data) {
              return { ok: res.ok, data: data };
            });
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
          setStatus("✅ erfolgreich übermittelt", false);
          setTimeout(function() { location.reload(); }, 1200);
        })
        .catch(function(err) {
          var msg = (err && err.message) ? err.message : String(err);
          setStatus("❌ " + msg, true);
          uploadBtn.disabled = false;
          takePhotoBtn.disabled = false;
          abortBtn.disabled = false;
        });
    });

    abortBtn.addEventListener("click", function () {
      if (!confirm("Vorgang wirklich abbrechen? Die Anforderung wird gelöscht.")) return;

      uploadBtn.disabled = true;
      takePhotoBtn.disabled = true;
      abortBtn.disabled = true;
      setStatus("Abbruch läuft…", false);

      var formData = new FormData();
      formData.append("action", "abort");
      formData.append("session_id", SESSION_ID);

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
          uploadBtn.disabled = false;
          takePhotoBtn.disabled = false;
          abortBtn.disabled = false;
        });
    });
  </script>
</body>
</html>
