<?php
declare(strict_types=1);

/*
 * selfie.php v1.9
 *
 * Changelog (since v1.2)
 * - v1.2: Upload + Schreiben selfie.jpg + Antwort-GDT 6310 (6302–6305)
 * - v1.3: Zielpfad fix: /srv/fragebogenpi/GDT
 * - v1.4: Auto-Refresh alle 3s, wenn keine Auftrags-GDT vorhanden
 * - v1.5: Nach erfolgreicher Antwort: Auftrags-GDT löschen, Reload
 * - v1.6: Client-side Downscale (Canvas) statt Server-GD
 * - v1.7: UI: Patient groß, Abbruch-Button, Entfernt 6228
 * - v1.8: 6304="Selfie", Versionsanzeige im UI
 * - v1.9: Akzeptiert ausschließlich SLFT2MD.gdt als Auftragsdatei
 */

$APP_FOOTER  = 'fragebogenpi (selfie.php) von Dr. Thomas Kienzle 2026';
$APP_VERSION = 'v1.9';

$dirPdf = '/srv/fragebogenpi/GDT';
$REQUEST_GDT_NAME = 'SLFT2MD.gdt';
$ANSWER_GDT_NAME  = 'T2MDSLF.gdt';
$IMAGE_NAME       = 'selfie.jpg';

/* ---------- helpers ---------- */
function h(string $s): string {
    return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
function json_out(int $code, array $payload): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
}
function gdt_line(string $field4, string $value): string {
    $rest = $field4 . $value;
    return str_pad((string)(3 + strlen($rest)), 3, '0', STR_PAD_LEFT) . $rest;
}
function parse_gdt(string $path): array {
    $raw = file_get_contents($path);
    if ($raw === false) return [];
    $raw = str_replace("\r\n", "\n", $raw);
    $out = [];
    foreach (explode("\n", $raw) as $line) {
        if (strlen($line) < 7) continue;
        $rest = substr($line, 3);
        $out[substr($rest, 0, 4)] = substr($rest, 4);
    }
    return $out;
}
function write_gdt(string $path, array $lines): void {
    $tmp = implode("\n", $lines) . "\n";
    $len = str_pad((string)strlen($tmp), 6, '0', STR_PAD_LEFT);
    foreach ($lines as &$l) {
        if (substr($l, 3, 4) === '8100') {
            $l = gdt_line('8100', $len);
            break;
        }
    }
    file_put_contents($path, implode("\n", $lines) . "\n");
}

/* ---------- paths ---------- */
$requestPath = $dirPdf . '/' . $REQUEST_GDT_NAME;
$hasRequest  = is_file($requestPath);
$req         = $hasRequest ? parse_gdt($requestPath) : [];

$vorname  = $req['3102'] ?? '';
$nachname = $req['3101'] ?? '';
$patient  = trim("$vorname $nachname");
if ($patient === '') $patient = '—';

/* ---------- POST ---------- */
if ($_SERVER['REQUEST_METHOD'] === 'POST') {

    if (($_POST['action'] ?? '') === 'abort') {
        if ($hasRequest) @unlink($requestPath);
        json_out(200, ['status' => 'ok', 'message' => 'abgebrochen']);
    }

    if (!$hasRequest) {
        json_out(409, ['status' => 'error', 'message' => 'Keine gültige SLFT2MD.gdt vorhanden']);
    }

    if (!isset($_FILES['image']) || $_FILES['image']['error'] !== UPLOAD_ERR_OK) {
        json_out(400, ['status' => 'error', 'message' => 'Upload fehlgeschlagen']);
    }

    $finfo = new finfo(FILEINFO_MIME_TYPE);
    if ($finfo->file($_FILES['image']['tmp_name']) !== 'image/jpeg') {
        json_out(400, ['status' => 'error', 'message' => 'Nur JPEG erlaubt']);
    }

    move_uploaded_file($_FILES['image']['tmp_name'], "$dirPdf/$IMAGE_NAME");

    $lines = [
        gdt_line('8000','6310'),
        gdt_line('8100','000000'),
        gdt_line('8315',$req['8316'] ?? 'T2MED_PX'),
        gdt_line('8316',$req['8315'] ?? 'KIMP_GDT'),
        gdt_line('9206','2'),
        gdt_line('9218','02.10'),
        gdt_line('3000',$req['3000'] ?? ''),
        gdt_line('3101',$nachname),
        gdt_line('3102',$vorname),
        gdt_line('8402',$req['8402'] ?? 'ALLG0'),
        gdt_line('6200','KI01'),
        gdt_line('6201','KI-Selfie'),
        gdt_line('6302','000001'),
        gdt_line('6303','JPG'),
        gdt_line('6304','Selfie'),
        gdt_line('6305',$IMAGE_NAME),
        gdt_line('9999',''),
    ];

    write_gdt("$dirPdf/$ANSWER_GDT_NAME", $lines);
    @unlink($requestPath);

    json_out(200, ['status'=>'ok','message'=>'erfolgreich übermittelt']);
}

/* ---------- GET ---------- */
?>
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Selfie</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f2f2f7;padding:20px;text-align:center}
.card{background:#fff;border-radius:14px;padding:16px;max-width:380px;margin:auto}
.patient{font-size:2.2rem;font-weight:900}
.footer{margin-top:14px;font-size:.8rem;color:#777}
</style>
<?php if(!$hasRequest): ?><meta http-equiv="refresh" content="3"><?php endif; ?>
</head>
<body>
<div class="card">
  <div class="patient"><?=h($patient)?></div>

<?php if(!$hasRequest): ?>
  <p>Warte auf Auftrag <b>SLFT2MD.gdt</b><br>Seite aktualisiert sich automatisch.</p>
<?php else: ?>
  <input id="cam" type="file" accept="image/*" capture="user" hidden>
  <button onclick="cam.click()">📷 Selfie aufnehmen</button>
  <button onclick="upload()" id="up" disabled>⬆️ Upload</button>
  <button onclick="abort()">❌ Abbruch</button>
  <p id="st"></p>
<?php endif; ?>

  <div class="footer"><?=$APP_FOOTER?> · <?=$APP_VERSION?></div>
</div>

<script>
var cam=document.getElementById('cam'),up=document.getElementById('up'),st=document.getElementById('st'),file;
if(cam){
  cam.onchange=e=>{file=e.target.files[0];up.disabled=!file;}
}
function upload(){
  st.textContent='Upload läuft…';
  let i=new Image(); i.onload=()=>{
    let s=Math.min(1,800/Math.max(i.width,i.height));
    let c=document.createElement('canvas');
    c.width=i.width*s;c.height=i.height*s;
    c.getContext('2d').drawImage(i,0,0,c.width,c.height);
    c.toBlob(b=>{
      let fd=new FormData(); fd.append('image',b,'selfie.jpg');
      fetch('',{method:'POST',body:fd}).then(r=>r.json()).then(()=>{
        st.textContent='✅ erfolgreich übermittelt';
        setTimeout(()=>location.reload(),1200);
      });
    },'image/jpeg',0.82);
  };
  i.src=URL.createObjectURL(file);
}
function abort(){
  if(!confirm('Auftrag abbrechen?'))return;
  fetch('',{method:'POST',body:new URLSearchParams({action:'abort'})})
    .then(()=>location.reload());
}
</script>
</body>
</html>
