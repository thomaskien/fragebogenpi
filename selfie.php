<?php
declare(strict_types=1);

/*
 * selfie.php v1.8
 *
 * Changelog (since v1.2)
 * - v1.2: Upload + Schreiben selfie.jpg + Antwort-GDT 6310 (6302–6305) im selben Ordner
 * - v1.3: Zielpfad fix: /srv/fragebogenpi/GDT, Suche nach Auftrags-GDT ebenfalls dort
 * - v1.4: Auto-Refresh alle 3s, wenn keine Auftrags-GDT vorhanden
 * - v1.5: Nach erfolgreicher Antwort: Auftrags-GDT löschen, UI zeigt "erfolgreich übermittelt" und lädt neu
 * - v1.6: Client-side Downscale (Canvas) statt Server-GD, da GD fehlt
 * - v1.7: UI: Patient (Vorname Nachname) ganz groß oben, entfernte Hinweis-/Endpoint-Blöcke,
 *         Abbruch-Button, Downscale max. Kante 800px, Entfernt 6228
 * - v1.8: Feld 6304 wieder gesetzt auf Beschreibung "Selfie",
 *         Versionsanzeige in UI ergänzt und inkrementiert
 */

$APP_FOOTER  = 'fragebogenpi (selfie.php) von Dr. Thomas Kienzle 2026';
$APP_VERSION = 'v1.8';

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

function write_gdt_file(string $path, array $lines): void {
    $joined = implode("\n", $lines) . "\n";
    $totalBytes = strlen($joined);
    $total6 = str_pad((string)$totalBytes, 6, '0', STR_PAD_LEFT);

    foreach ($lines as $i => $line) {
        if (substr($line, 3, 4) === '8100') {
            $lines[$i] = gdt_line('8100', $total6);
            break;
        }
    }

    file_put_contents($path, implode("\n", $lines) . "\n");
}

function find_request_gdt(string $gdtDir, string $ignoreBasename): ?string {
    $files = glob(rtrim($gdtDir, '/') . '/*.gdt') ?: [];
    $files = array_values(array_filter($files, fn($p) => basename($p) !== $ignoreBasename));
    if (!$files) return null;
    usort($files, fn($a, $b) => filemtime($b) <=> filemtime($a));
    return $files[0];
}

// ----------------- dir checks -----------------
if (!is_dir($dirPdf)) @mkdir($dirPdf, 0775, true);

// ----------------- request gdt -----------------
$requestPath = find_request_gdt($dirPdf, $OUT_GDT_NAME);
$reqFields   = ($requestPath && is_file($requestPath)) ? parse_gdt($requestPath) : [];

$vorname  = $reqFields['3102'] ?? '';
$nachname = $reqFields['3101'] ?? '';
$displayName = trim($vorname . ' ' . $nachname);
if ($displayName === '') $displayName = '—';

// ----------------- POST -----------------
if ($_SERVER['REQUEST_METHOD'] === 'POST') {

    // ---- ABBRUCH ----
    if (($_POST['action'] ?? '') === 'abort') {
        if ($requestPath && is_file($requestPath)) @unlink($requestPath);
        json_out(200, ['status' => 'ok', 'message' => 'abgebrochen']);
    }

    if (!$requestPath || !is_file($requestPath)) {
        json_out(409, ['status' => 'error', 'message' => 'Keine Auftrags-GDT gefunden']);
    }

    if (!isset($_FILES['image']) || $_FILES['image']['error'] !== UPLOAD_ERR_OK) {
        json_out(400, ['status' => 'error', 'message' => 'Bild fehlt oder Upload-Fehler']);
    }

    $file = $_FILES['image'];
    $finfo = new finfo(FILEINFO_MIME_TYPE);
    if ($finfo->file($file['tmp_name']) !== 'image/jpeg') {
        json_out(400, ['status' => 'error', 'message' => 'Nur JPEG erlaubt']);
    }

    $targetJpg = $dirPdf . '/' . $OUT_JPG_NAME;
    if (!move_uploaded_file($file['tmp_name'], $targetJpg)) {
        json_out(500, ['status' => 'error', 'message' => 'Speichern fehlgeschlagen']);
    }

    // GDT-Felder
    $patId3000 = $reqFields['3000'] ?? '';
    if ($patId3000 === '') json_out(422, ['status' => 'error', 'message' => 'Patienten-ID fehlt']);

    $ans8315 = $reqFields['8316'] ?? 'T2MED_PX';
    $ans8316 = $reqFields['8315'] ?? 'KIMP_GDT';
    $kennfeld = $reqFields['8402'] ?? 'ALLG0';

    // Antwort-GDT
    $lines = [
        gdt_line('8000', '6310'),
        gdt_line('8100', '000000'),
        gdt_line('8315', $ans8315),
        gdt_line('8316', $ans8316),
        gdt_line('9206', '2'),
        gdt_line('9218', '02.10'),
        gdt_line('3000', $patId3000),
        gdt_line('3101', $nachname),
        gdt_line('3102', $vorname),
        gdt_line('8402', $kennfeld),
        gdt_line('6200', 'KI01'),
        gdt_line('6201', 'KI-Selfie'),
        gdt_line('6302', '000001'),
        gdt_line('6303', 'JPG'),
        gdt_line('6304', 'Selfie'),   // ← wieder gesetzt
        gdt_line('6305', $OUT_JPG_NAME),
        gdt_line('9999', ''),
    ];

    write_gdt_file($dirPdf . '/' . $OUT_GDT_NAME, $lines);
    @unlink($requestPath);

    json_out(200, ['status' => 'ok', 'message' => 'erfolgreich übermittelt']);
}

// ----------------- GET (UI) -----------------
?>
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Selfie Upload</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f2f2f7;margin:0;padding:20px;text-align:center}
.card{background:#fff;border-radius:14px;padding:16px;max-width:380px;margin:auto;box-shadow:0 6px 18px rgba(0,0,0,.06)}
.patient{font-size:2.2rem;font-weight:900;margin-bottom:10px}
button{width:100%;padding:14px;border-radius:12px;border:none;font-size:1rem;margin:8px 0}
#takePhotoBtn{background:#007aff;color:#fff}
#uploadBtn{background:#34c759;color:#fff}
#abortBtn{background:#ff3b30;color:#fff}
#uploadBtn:disabled{opacity:.5}
#preview{display:none;margin-top:10px;width:100%;border-radius:12px}
#status{margin-top:10px;font-weight:700}
.footer{margin-top:14px;font-size:.8rem;color:#777}
</style>
</head>
<body>
<div class="card">
  <div class="patient"><?=h($displayName)?></div>

<?php if (!$requestPath): ?>
  <div>Warte auf Auftragsdatei…<br>Seite aktualisiert sich automatisch.</div>
  <meta http-equiv="refresh" content="3">
<?php else: ?>
  <input id="cameraInput" type="file" accept="image/*" capture="user" style="display:none">
  <button id="takePhotoBtn">📷 Selfie aufnehmen</button>
  <button id="uploadBtn" disabled>⬆️ Upload</button>
  <button id="abortBtn">❌ Abbruch</button>
  <img id="preview">
  <div id="status"></div>
<?php endif; ?>

  <div class="footer"><?=h($APP_FOOTER . ' · ' . $APP_VERSION)?></div>
</div>

<script>
var input=document.getElementById('cameraInput');
var take=document.getElementById('takePhotoBtn');
var up=document.getElementById('uploadBtn');
var abortBtn=document.getElementById('abortBtn');
var prev=document.getElementById('preview');
var status=document.getElementById('status');
var file=null;

if(take){
  take.onclick=()=>input.click();
  input.onchange=e=>{
    file=e.target.files[0];
    if(!file)return;
    prev.src=URL.createObjectURL(file);
    prev.style.display='block';
    up.disabled=false;
  };

  function downscale(f){
    return new Promise((res,rej)=>{
      var img=new Image();
      img.onload=()=>{
        var m=800,s=Math.min(1,m/Math.max(img.width,img.height));
        var c=document.createElement('canvas');
        c.width=img.width*s;c.height=img.height*s;
        c.getContext('2d').drawImage(img,0,0,c.width,c.height);
        c.toBlob(b=>res(b),'image/jpeg',0.82);
      };
      img.src=URL.createObjectURL(f);
    });
  }

  up.onclick=()=>{
    status.textContent='Upload läuft…';
    downscale(file).then(b=>{
      var fd=new FormData();
      fd.append('image',b,'selfie.jpg');
      return fetch(location.pathname,{method:'POST',body:fd});
    }).then(r=>r.json()).then(j=>{
      status.textContent='✅ erfolgreich übermittelt';
      setTimeout(()=>location.reload(),1200);
    }).catch(e=>status.textContent='❌ '+e);
  };

  abortBtn.onclick=()=>{
    if(!confirm('Vorgang abbrechen?'))return;
    fetch(location.pathname,{method:'POST',body:new URLSearchParams({action:'abort'})})
      .then(()=>location.reload());
  };
}
</script>
</body>
</html>
