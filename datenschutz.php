<?php
/**
 * datenschutz.php
 * fragebogenpi.de - Datenschutz/DSGVO-Unterschrift auf dem iPad
 *
 * Version: 1.1
 * Autor: Dr. Thomas Kienzle
 *
 * Changelog (vollstaendig):
 * - v1.0:
 *   + Erstversion als konservatives fragebogenpi-Modul.
 *   + Urspruengliche feste Dateinamen: dsgvo-in.gdt und dsgvo-out.gdt.
 *   + YAML-Konfiguration ueber datenschutz.yaml.
 *   + iPad-taugliche Weboberflaeche mit Unterschriftsfeld per Canvas.
 *   + Serverseitige PDF-Erzeugung ueber extern installiertes TCPDF-Paket.
 *   + Keine eingebettete PDF-Bibliothek in dieser Datei.
 *   + PDF-Dateiname nach Muster Datenschutz_patientennummer_zeitstempel.pdf.
 *   + PDF-Rueckgabe per GDT-Dateiverweis nach Muster aus befund.php.
 *   + GDT-Grundstruktur, Patientendaten und 3000/0193-Logik angelehnt an anamnesebogen.php.
 *   + Zeitstempel/Protokollinformationen im PDF-Footer.
 * - v1.0.1-test:
 *   + YAML aus dem zentralen Formularverzeichnis, mit lokaler Test-Fallbackdatei.
 *   + Unterschrift und erfolgreiche PDF-Erzeugung sind zwingend.
 *   + Optionale E-Mail-Einwilligung wird als Ja/Nein in der PDF dokumentiert.
 *   + PDF-Import per GDT 6302-6305 an den funktionierenden Befundbildweg angeglichen.
 * - v1.0.2-test:
 *   + Transparenter Aufruf durch tablet.php mit Rueckkehr zur Tablet-Warteschlange.
 *   + Dateinamen zunaechst auf dsgv-in.gdt und dsgv-out.gdt geaendert.
 *   + Unterschriftsbereich dauerhaft am unteren Bildschirmrand fixiert.
 * - v1.0.3-test:
 *   + Zweite optionale Einwilligung fuer SMS ergaenzt.
 *   + SMS- und E-Mail-Status werden gemeinsam in PDF und GDT dokumentiert.
 * - v1.0.4-test:
 *   + Dateinamen auf dsgv-i.gdt und dsgv-o.gdt vereinheitlicht.
 *   + SMS- und E-Mail-Checkbox bleiben zusammen mit dem Unterschriftsfeld fixiert.
 * - v1.0.5-test:
 *   + Unterschrift mit Touch- und Maus-Fallback fuer aeltere Tablet-Browser.
 *   + Fixierter Bereich ohne CSS-Transform, damit Formularelemente anklickbar bleiben.
 *   + Unterschriftsfeld erhoeht und Einwilligungstexte einzeilig dargestellt.
 * - v1.0.6-test:
 *   + Erklaerungstext wieder als eigener abgegrenzter Scrollbereich.
 *   + Scrollen der gesamten Seite verhindert; Einwilligungen und Unterschrift bleiben stehen.
 * - v1.0.7-test:
 *   + Gesamter oberer Bereich einschliesslich Patientendaten gemeinsam scrollbar.
 *   + Beide Einwilligungscheckboxen linksbuendig nebeneinander angeordnet.
 * - v1.0.8-test:
 *   + Separaten Momentum-Scrollcontainer entfernt, der auf alten iPads Touch am
 *     darin verschachtelten fixierten Unterschriftsfeld blockieren konnte.
 *   + Oberen Seitenbereich normal scrollbar und Unterschriftsfeld deutlich hoeher.
 * - v1.0.9-test:
 *   + Formularversion sichtbar in PDF-Inhalt und PDF-Fusszeile aufgenommen.
 *   + Checkboxabstaende mit altbrowserkompatiblen Margins statt Flex-Gap.
 * - v1.0.10-test:
 *   + Automatisches Leeren der Unterschrift durch Browser-Resize-Ereignisse verhindert.
 *   + Checkboxabstaende durch explizites Padding browserunabhaengig festgelegt.
 * - v1.1:
 *   + Technischen Teststand als stabile Programmversion 1.1 zusammengefuehrt.
 *   + Versionssuffix "test" aus der sichtbaren PHP-Programmversion entfernt.
 *   + Programm- und Formularversion werden gemeinsam im PDF-Footer ausgegeben.
 *   + Deutlicher Hinweisbanner bleibt unabhaengig von der Versionsbezeichnung erhalten.
 */

declare(strict_types=1);

$APP_FOOTER = 'fragebogenpi.de von Dr. Thomas Kienzle 2026';
$APP_VERSION = 'v1.1 (datenschutz.php)';

$dirGdt = '/srv/fragebogenpi/GDT';
$requestedGdt = basename((string)($_GET['request_gdt'] ?? 'dsgv-i.gdt'));
$REQUEST_GDT_NAME = preg_match('/^(?:[1-9]-)?dsgv-i\\.gdt$/', $requestedGdt) ? $requestedGdt : 'dsgv-i.gdt';
$OUT_GDT_NAME = preg_replace('/-i\\.gdt$/', '-o.gdt', $REQUEST_GDT_NAME) ?: 'dsgv-o.gdt';
$RETURN_TO = basename((string)($_GET['return_to'] ?? 'tablet.php'));
if (!preg_match('/^tablet(?:[1-9])?\\.php$/', $RETURN_TO)) $RETURN_TO = 'tablet.php';
$YAML_PATH = '/srv/fragebogenpi/formulare/datenschutz.yaml';
if (!is_file($YAML_PATH) && is_file(__DIR__ . '/_yaml/datenschutz.yaml')) {
    $YAML_PATH = __DIR__ . '/_yaml/datenschutz.yaml';
}

$DEFAULT_8315 = 'BOGI_GDT';
$DEFAULT_8316 = 'BIMP_GDT';
$ANSWER_6200 = 'DSGVO1';
$ANSWER_6201 = 'Datenschutz';
$UI_TITLE = 'Datenschutz (iPad)';
$MAX_6228_BYTES = 70;

// ----------------- helpers -----------------
function h(string $s): string {
    return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function is_valid_utf8(string $s): bool {
    return $s === '' ? true : (bool)@preg_match('//u', $s);
}

function req_to_utf8_for_ui(string $raw): string {
    if ($raw === '') return '';
    if (is_valid_utf8($raw)) return $raw;
    if (function_exists('iconv')) {
        foreach (['CP437', 'ISO-8859-1', 'Windows-1252'] as $enc) {
            $tmp = @iconv($enc, 'UTF-8//IGNORE', $raw);
            if ($tmp !== false && $tmp !== '') return $tmp;
        }
    }
    return $raw;
}

function ascii_only(string $s): string {
    $map = [
        'Ä'=>'Ae','Ö'=>'Oe','Ü'=>'Ue','ä'=>'ae','ö'=>'oe','ü'=>'ue','ß'=>'ss',
        '’'=>"'","´"=>"'","`"=>"'","“"=>'"',"”"=>'"',"„"=>'"',"–"=>'-',"—"=>'-',"…"=>'...',
    ];
    $s = strtr($s, $map);
    if (function_exists('iconv')) {
        $tmp = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $s);
        if ($tmp !== false && $tmp !== '') $s = $tmp;
    }
    $s = preg_replace('/[^\x20-\x7E]/', '?', $s) ?? $s;
    return $s;
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

function req_value_passthrough(string $s, int $maxLen = 200): string {
    $s = str_replace(["\r", "\n", "\t"], ' ', $s);
    $s = preg_replace('/\s+/', ' ', $s) ?? $s;
    $s = trim($s);
    if (strlen($s) > $maxLen) $s = substr($s, 0, $maxLen);
    return $s;
}

function format_gebdat(string $s): string {
    $digits = preg_replace('/\D+/', '', $s) ?? '';
    if (strlen($digits) >= 8) $digits = substr($digits, 0, 8);
    if (strlen($digits) !== 8) return ($s !== '' ? $s : '—');
    return substr($digits, 0, 2) . '.' . substr($digits, 2, 2) . '.' . substr($digits, 4, 4);
}

function json_out(int $code, array $payload): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        $json = json_encode(['status'=>'error','message'=>'json_encode fehlgeschlagen'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '{"status":"error","message":"json_encode failed"}';
    }
    echo $json;
    exit;
}

function gdt_line(string $field4, string $value): string {
    $rest = $field4 . $value;
    $len = 3 + strlen($rest); // wie beim funktionierenden Befundbildimport
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
        $rest = substr($line, 3);
        $field = substr($rest, 0, 4);
        $value = substr($rest, 4);
        $fields[$field] = $value; // raw bytes beibehalten
    }
    return $fields;
}

function write_gdt_file(string $path, array $lines): void {
    $joined = implode("\r\n", $lines) . "\r\n";
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
    $joined2 = implode("\r\n", $lines) . "\r\n";
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
        $joined2 = implode("\r\n", $lines) . "\r\n";
    }
    file_put_contents($path, $joined2);
}

function to_ascii_wrapped_lines(string $s, int $maxBytes): array {
    $s = ascii_only(clean_utf8_text($s, 5000));
    if (strlen($s) <= $maxBytes) return [$s];
    $words = preg_split('/\s+/', $s) ?: [];
    $out = [];
    $cur = '';
    foreach ($words as $w) {
        $try = ($cur === '') ? $w : ($cur . ' ' . $w);
        if (strlen($try) <= $maxBytes) {
            $cur = $try;
            continue;
        }
        if ($cur !== '') {
            $out[] = $cur;
            $cur = $w;
            continue;
        }
        $out[] = substr($w, 0, $maxBytes);
        $cur = '';
    }
    if ($cur !== '') $out[] = $cur;
    return $out;
}

function yaml_load_or_die(string $path): array {
    if (!is_file($path)) return ['__error' => 'YAML-Datei nicht gefunden: ' . $path];
    if (!function_exists('yaml_parse_file')) return ['__error' => 'PHP YAML Extension fehlt (yaml_parse_file nicht verfuegbar). Bitte php-yaml installieren.'];
    $data = @yaml_parse_file($path);
    if (!is_array($data)) return ['__error' => 'YAML konnte nicht geparst werden oder ist leer/ungueltig.'];
    return $data;
}

function safe_filename_part(string $s): string {
    $s = ascii_only(req_to_utf8_for_ui($s));
    $s = preg_replace('/[^A-Za-z0-9_.-]+/', '_', $s) ?? $s;
    $s = trim($s, '._-');
    return $s !== '' ? $s : 'unbekannt';
}

function require_tcpdf_or_error(): ?string {
    $candidates = [
        '/usr/share/php/tcpdf/autoload.php',
        '/usr/share/php/tcpdf/tcpdf.php',
        __DIR__ . '/vendor/autoload.php',
    ];
    foreach ($candidates as $p) {
        if (is_file($p)) {
            require_once $p;
            if (class_exists('TCPDF')) return null;
        }
    }
    if (!class_exists('TCPDF')) {
        return 'TCPDF nicht gefunden. Bitte php-tcpdf installieren.';
    }
    return null;
}

function signature_data_to_png_file(string $dataUrl): array {
    if (!preg_match('#^data:image/png;base64,#', $dataUrl)) {
        return [null, 'Unterschrift wurde nicht als PNG empfangen.'];
    }
    $base64 = substr($dataUrl, strlen('data:image/png;base64,'));
    $bin = base64_decode($base64, true);
    if ($bin === false || strlen($bin) < 100) {
        return [null, 'Unterschriftsdaten sind leer oder ungueltig.'];
    }
    if (substr($bin, 0, 8) !== "\x89PNG\r\n\x1a\n") {
        return [null, 'Unterschriftsdaten sind kein gueltiges PNG.'];
    }
    $tmp = tempnam(sys_get_temp_dir(), 'dsgvo_sig_');
    if ($tmp === false) return [null, 'Temporaere Datei fuer Unterschrift konnte nicht erzeugt werden.'];
    $png = $tmp . '.png';
    @rename($tmp, $png);
    if (file_put_contents($png, $bin) === false) {
        return [null, 'Unterschrift konnte nicht temporaer gespeichert werden.'];
    }
    return [$png, null];
}

function yaml_text_blocks(array $yaml): array {
    $doc = $yaml['document'] ?? [];
    if (!is_array($doc)) $doc = [];
    $blocks = [];
    $heading = (string)($doc['heading'] ?? ($yaml['meta']['title'] ?? 'Datenschutzerklaerung'));
    $intro = (string)($doc['intro'] ?? '');
    $blocks[] = ['type' => 'heading', 'text' => $heading];
    if ($intro !== '') $blocks[] = ['type' => 'paragraph', 'text' => $intro];
    $sections = $doc['sections'] ?? [];
    if (is_array($sections)) {
        foreach ($sections as $sec) {
            if (!is_array($sec)) continue;
            $title = (string)($sec['title'] ?? '');
            $text = (string)($sec['text'] ?? '');
            if ($title !== '') $blocks[] = ['type' => 'section_title', 'text' => $title];
            if ($text !== '') $blocks[] = ['type' => 'paragraph', 'text' => $text];
        }
    }
    return $blocks;
}

if (!class_exists('DatenschutzTcpdf', false) && class_exists('TCPDF')) {
    class DatenschutzTcpdf extends TCPDF {
        public string $fragebogenFooter = '';
        public string $protocolFooter = '';
        public function Header(): void {}
        public function Footer(): void {
            $this->SetY(-20);
            $this->SetFont('dejavusans', '', 7);
            $this->SetTextColor(90, 90, 90);
            $txt = trim($this->protocolFooter . "\n" . $this->fragebogenFooter);
            $this->MultiCell(0, 4, $txt, 0, 'C', false, 1, '', '', true, 0, false, true, 12, 'M');
        }
    }
}

function make_pdf(string $targetPath, array $yaml, array $patient, string $signaturePng, bool $emailConsent, bool $smsConsent, string $protocolFooter, string $appFooter, string $appVersion): void {
    $err = require_tcpdf_or_error();
    if ($err !== null) throw new RuntimeException($err);

    if (!class_exists('DatenschutzTcpdf', false)) {
        class DatenschutzTcpdf extends TCPDF {
            public string $fragebogenFooter = '';
            public string $protocolFooter = '';
            public function Header(): void {}
            public function Footer(): void {
                $this->SetY(-20);
                $this->SetFont('dejavusans', '', 7);
                $this->SetTextColor(90, 90, 90);
                $txt = trim($this->protocolFooter . "\n" . $this->fragebogenFooter);
                $this->MultiCell(0, 4, $txt, 0, 'C', false, 1, '', '', true, 0, false, true, 12, 'M');
            }
        }
    }

    $meta = $yaml['meta'] ?? [];
    if (!is_array($meta)) $meta = [];
    $pdfTitle = (string)($meta['pdf_title'] ?? $meta['title'] ?? 'Datenschutzerklaerung');

    $formVersion = trim((string)($meta['version'] ?? ''));

    $pdf = new DatenschutzTcpdf('P', 'mm', 'A4', true, 'UTF-8', false);
    $pdf->fragebogenFooter = $appFooter
        . ' | Programmversion: ' . $appVersion
        . ($formVersion !== '' ? ' | Formularversion: ' . $formVersion : '');
    $pdf->protocolFooter = $protocolFooter;
    $pdf->SetCreator('fragebogenpi.de');
    $pdf->SetAuthor('fragebogenpi.de');
    $pdf->SetTitle($pdfTitle);
    $pdf->SetMargins(18, 18, 18);
    $pdf->SetAutoPageBreak(true, 24);
    $pdf->AddPage();
    $pdf->SetTextColor(20, 20, 20);

    $pdf->SetFont('dejavusans', 'B', 16);
    $pdf->Write(8, $pdfTitle);
    $pdf->Ln(10);

    if ($formVersion !== '') {
        $pdf->SetFont('dejavusans', '', 8);
        $pdf->SetTextColor(90, 90, 90);
        $pdf->Write(5, 'Formularversion: ' . $formVersion);
        $pdf->Ln(7);
        $pdf->SetTextColor(20, 20, 20);
    }

    $noticeBanner = trim((string)($meta['warning_notice'] ?? ''));
    if ($noticeBanner !== '') {
        $pdf->SetTextColor(176, 0, 32);
        $pdf->SetFont('dejavusans', 'B', 10);
        $pdf->MultiCell(0, 6, $noticeBanner, 1, 'L', false, 1);
        $pdf->Ln(3);
        $pdf->SetTextColor(20, 20, 20);
    }

    $pdf->SetFont('dejavusans', '', 10);
    $patientHtml = '<table cellpadding="3" cellspacing="0" border="0">'
        . '<tr><td width="35%"><b>Patient</b></td><td>' . h($patient['display_name'] ?? '—') . '</td></tr>'
        . '<tr><td><b>Geburtsdatum</b></td><td>' . h($patient['birthdate'] ?? '—') . '</td></tr>'
        . '<tr><td><b>Patientennummer</b></td><td>' . h($patient['patient_no'] ?? '—') . '</td></tr>'
        . '</table><br>';
    $pdf->writeHTML($patientHtml, true, false, true, false, '');

    foreach (yaml_text_blocks($yaml) as $block) {
        $type = $block['type'];
        $text = (string)$block['text'];
        if ($type === 'heading') {
            $pdf->SetFont('dejavusans', 'B', 14);
            $pdf->Write(7, $text);
            $pdf->Ln(8);
        } elseif ($type === 'section_title') {
            $pdf->Ln(2);
            $pdf->SetFont('dejavusans', 'B', 11);
            $pdf->Write(6, $text);
            $pdf->Ln(6);
        } else {
            $pdf->SetFont('dejavusans', '', 10);
            $html = '<div style="line-height:1.35; text-align:left;">' . nl2br(h($text)) . '</div>';
            $pdf->writeHTML($html, true, false, true, false, '');
        }
    }

    $consent = $yaml['consent'] ?? [];
    if (!is_array($consent)) $consent = [];
    $emailLabel = (string)($consent['pdf_label'] ?? $consent['checkbox_label'] ?? 'Optionale E-Mail-Einwilligung');
    $smsLabel = (string)($consent['sms_pdf_label'] ?? $consent['sms_checkbox_label'] ?? 'Optionale SMS-Einwilligung');
    $emailStatus = $emailConsent ? 'JA' : 'NEIN';
    $smsStatus = $smsConsent ? 'JA' : 'NEIN';
    $pdf->Ln(4);
    $pdf->SetFont('dejavusans', '', 10);
    $pdf->writeHTML(
        '<b>Optionale Kommunikationseinwilligungen:</b><br>'
        . h($smsLabel) . ': ' . $smsStatus . '<br>'
        . h($emailLabel) . ': ' . $emailStatus,
        true,
        false,
        true,
        false,
        ''
    );

    $pdf->Ln(6);
    $pdf->SetFont('dejavusans', 'B', 10);
    $pdf->Write(6, 'Unterschrift des Patienten / der Patientin:');
    $pdf->Ln(8);
    $x = $pdf->GetX();
    $y = $pdf->GetY();
    $pdf->Image($signaturePng, $x, $y, 75, 28, 'PNG');
    $pdf->SetY($y + 31);
    $pdf->SetFont('dejavusans', '', 8);
    $pdf->Cell(80, 5, 'Unterschrift', 'T', 0, 'C');

    $pdf->Output($targetPath, 'F');
}

// ----------------- dir checks -----------------
if (!is_dir($dirGdt)) @mkdir($dirGdt, 0775, true);
if ((!is_dir($dirGdt) || !is_writable($dirGdt)) && $_SERVER['REQUEST_METHOD'] === 'POST') {
    json_out(500, ['status'=>'error','message'=>'Zielverzeichnis existiert nicht oder ist nicht beschreibbar','dir'=>$dirGdt]);
}

// ----------------- request gdt -----------------
$requestPath = rtrim($dirGdt, '/') . '/' . $REQUEST_GDT_NAME;
$hasRequest = is_file($requestPath);
$reqFields = $hasRequest ? parse_gdt($requestPath) : [];

$vorname_raw = $reqFields['3102'] ?? '';
$nachname_raw = $reqFields['3101'] ?? '';
$gebdat_raw = $reqFields['3103'] ?? '';
$vorname_ui = req_to_utf8_for_ui($vorname_raw);
$nachname_ui = req_to_utf8_for_ui($nachname_raw);
$gebdat_ui = format_gebdat(req_to_utf8_for_ui($gebdat_raw));
$displayName_ui = trim(trim($vorname_ui . ' ' . $nachname_ui));
if ($displayName_ui === '') $displayName_ui = '—';

$patId3000 = $reqFields['3000'] ?? '';
$req0193 = $reqFields['0193'] ?? '';
$use3000_only = ($patId3000 !== '');
$use0193_only = (!$use3000_only && $req0193 !== '');
$ans3000 = $use3000_only ? $patId3000 : '';
$ans0193 = $use0193_only ? $req0193 : '';
$patientNoForFileRaw = ($ans3000 !== '') ? $ans3000 : $ans0193;
$patientNoForFile = safe_filename_part($patientNoForFileRaw);

$kennfeld = $reqFields['8402'] ?? 'ALLG0';
if ($kennfeld === '') $kennfeld = 'ALLG0';
$req8315 = $reqFields['8315'] ?? '';
$req8316 = $reqFields['8316'] ?? '';
$ans8315 = ($req8316 !== '') ? $req8316 : $DEFAULT_8315;
$ans8316 = ($req8315 !== '') ? $req8315 : $DEFAULT_8316;
$req4109 = $reqFields['4109'] ?? '';
$req4104 = $reqFields['4104'] ?? '';

$yaml = yaml_load_or_die($YAML_PATH);
$yamlError = $yaml['__error'] ?? null;

// ----------------- POST -----------------
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (($_POST['action'] ?? '') === 'abort') {
        $deleted = $hasRequest ? @unlink($requestPath) : false;
        json_out(200, ['status'=>'ok','message'=>'abgebrochen','request_deleted'=>$deleted,'request_gdt'=>$REQUEST_GDT_NAME]);
    }

    if (!$hasRequest) json_out(409, ['status'=>'error','message'=>'Keine Auftrags-GDT gefunden ('.$REQUEST_GDT_NAME.').']);
    if ($yamlError !== null) json_out(500, ['status'=>'error','message'=>$yamlError,'yaml'=>$YAML_PATH]);
    if ($ans3000 === '' && $ans0193 === '') json_out(422, ['status'=>'error','message'=>'Weder 3000 noch 0193 in der Auftrags-GDT vorhanden']);
    $emailConsent = (($_POST['email_consent'] ?? '') === 'yes');
    $smsConsent = (($_POST['sms_consent'] ?? '') === 'yes');

    [$sigPng, $sigErr] = signature_data_to_png_file((string)($_POST['signature_data'] ?? ''));
    if ($sigErr !== null || $sigPng === null) json_out(400, ['status'=>'error','message'=>$sigErr ?? 'Unterschrift fehlt.']);

    try {
        $timestamp = date('Ymd_His');
        $pdfName = 'Datenschutz_' . $patientNoForFile . '_' . $timestamp . '.pdf';
        $pdfPath = rtrim($dirGdt, '/') . '/' . $pdfName;
        $protocolFooter = 'Erzeugt: ' . date('d.m.Y H:i:s') . ' | Patientennummer: ' . $patientNoForFile . ' | Auftrag: ' . $REQUEST_GDT_NAME . ' | Datei: ' . $pdfName;
        $patient = [
            'display_name' => $displayName_ui,
            'birthdate' => $gebdat_ui,
            'patient_no' => req_to_utf8_for_ui($patientNoForFileRaw),
        ];
        make_pdf($pdfPath, $yaml, $patient, $sigPng, $emailConsent, $smsConsent, $protocolFooter, $APP_FOOTER, $APP_VERSION);
        @unlink($sigPng);
        if (!is_file($pdfPath) || filesize($pdfPath) === 0) {
            throw new RuntimeException('PDF wurde nicht erfolgreich erzeugt.');
        }
        $sha = hash_file('sha256', $pdfPath) ?: '';

        $lines = [];
        $lines[] = gdt_line('8000', '6310');
        $lines[] = gdt_line('8100', '000000');
        $lines[] = gdt_line('8315', $ans8315);
        $lines[] = gdt_line('8316', $ans8316);
        $lines[] = gdt_line('9206', '2');
        $lines[] = gdt_line('9218', '02.10');
        if ($ans3000 !== '') {
            $lines[] = gdt_line('3000', $ans3000);
        } elseif ($ans0193 !== '') {
            $lines[] = gdt_line('0193', $ans0193);
        }
        $lines[] = gdt_line('8402', $kennfeld);
        if ($nachname_raw !== '') $lines[] = gdt_line('3101', req_value_passthrough($nachname_raw, 120));
        if ($vorname_raw !== '') $lines[] = gdt_line('3102', req_value_passthrough($vorname_raw, 120));
        if ($gebdat_raw !== '') $lines[] = gdt_line('3103', req_value_passthrough($gebdat_raw, 40));
        if ($req4109 !== '') $lines[] = gdt_line('4109', $req4109);
        if ($req4104 !== '') $lines[] = gdt_line('4104', $req4104);
        $lines[] = gdt_line('6200', ascii_only($ANSWER_6200));
        $lines[] = gdt_line('6201', ascii_only($ANSWER_6201));
        foreach (to_ascii_wrapped_lines('Datenschutzerklaerung unterschrieben am ' . date('d.m.Y H:i:s') . '.', $MAX_6228_BYTES) as $l) {
            $lines[] = gdt_line('6228', $l);
        }
        $lines[] = gdt_line('6228', 'Datenschutzerklaerung:');
        $lines[] = gdt_line('6228', 'SMS: ' . ($smsConsent ? 'JA' : 'NEIN') . ' //  eMail: ' . ($emailConsent ? 'JA' : 'NEIN'));
        $lines[] = gdt_line('6302', '000001');
        $lines[] = gdt_line('6303', 'PDF');
        $lines[] = gdt_line('6304', 'Datenschutzerklaerung');
        $lines[] = gdt_line('6305', $pdfName);
        $lines[] = gdt_line('9999', '');

        $outGdtPath = rtrim($dirGdt, '/') . '/' . $OUT_GDT_NAME;
        write_gdt_file($outGdtPath, $lines);
        $deleted = @unlink($requestPath);

        json_out(200, [
            'status' => 'ok',
            'message' => 'Datenschutzerklaerung uebermittelt',
            'pdf' => $pdfName,
            'sha256' => $sha,
            'answer_gdt' => $OUT_GDT_NAME,
            'request_gdt' => $REQUEST_GDT_NAME,
            'request_deleted' => $deleted,
            'id_0193_used' => $ans0193,
            'id_3000_used' => $ans3000,
        ]);
    } catch (Throwable $e) {
        if (isset($sigPng) && is_string($sigPng)) @unlink($sigPng);
        json_out(500, ['status'=>'error','message'=>$e->getMessage()]);
    }
}

$meta = (isset($yaml['meta']) && is_array($yaml['meta'])) ? $yaml['meta'] : [];
$doc = (isset($yaml['document']) && is_array($yaml['document'])) ? $yaml['document'] : [];
$consent = (isset($yaml['consent']) && is_array($yaml['consent'])) ? $yaml['consent'] : [];
$docHeading = (string)($doc['heading'] ?? ($meta['title'] ?? 'Datenschutzerklaerung'));
$submitLabel = (string)($meta['submit_label'] ?? '✅ Datenschutzerklaerung unterschreiben und absenden');
$checkboxLabel = (string)($consent['checkbox_label'] ?? 'Optionale Einwilligung');
$smsCheckboxLabel = (string)($consent['sms_checkbox_label'] ?? 'Kontakt per SMS erlauben (Optional)');
$noticeBanner = trim((string)($meta['warning_notice'] ?? ''));
?>
<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="<?php echo h($UI_TITLE); ?>">
<title><?php echo h($UI_TITLE); ?></title>
<style>
:root{--bg:#f5f5f7;--card:#fff;--text:#1d1d1f;--muted:#6e6e73;--line:#d2d2d7;--accent:#0a7cff;--danger:#b00020;--ok:#0a7f37;}
*{box-sizing:border-box} html,body{min-height:100%} body{margin:0;padding:calc(env(safe-area-inset-top) + 22px) 18px 430px;overflow-y:auto;background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif;font-size:18px;line-height:1.45}.wrap{max-width:980px;margin:0 auto}.top{display:flex;justify-content:space-between;align-items:flex-end;gap:16px;margin-bottom:14px}.brand{font-weight:700;font-size:22px}.ver{font-size:13px;color:var(--muted);text-align:right}.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:20px;margin:14px 0;box-shadow:0 1px 2px rgba(0,0,0,.04)}h1{font-size:28px;margin:0 0 12px}h2{font-size:22px;margin:22px 0 8px}.muted{color:var(--muted)}.patient{display:grid;grid-template-columns:190px 1fr;gap:6px 14px}.err{color:var(--danger);font-weight:700}.ok{color:var(--ok);font-weight:700}.testnotice{border:2px solid var(--danger);border-radius:12px;background:#fff3f2;color:var(--danger);font-weight:800;padding:12px;margin-bottom:14px}.doc-text{border:1px solid var(--line);border-radius:12px;padding:16px;background:#fff}.doc-text p{margin:0 0 12px}.signatureDock{position:fixed;left:12px;right:12px;bottom:8px;bottom:max(8px,env(safe-area-inset-bottom));z-index:1000;width:auto;max-width:980px;margin:0 auto;background:#fff;border:2px solid #0a7cff;border-radius:16px;padding:10px 14px;box-shadow:0 -8px 28px rgba(0,0,0,.18)}.signatureDock h2{font-size:18px;margin:0 0 6px}.consentLines{display:flex;justify-content:flex-start;margin-bottom:8px}.checkline+.checkline{margin-left:20px}.sigbox{position:relative;border:2px solid var(--line);border-radius:10px;background:#fff;overflow:hidden;touch-action:none}.sigbox canvas{display:block;width:100%;height:210px;touch-action:none}.btns{display:flex;display:grid;grid-template-columns:1fr 2fr 1fr;gap:8px;margin-top:8px}.btns button{width:auto;flex:1 1 auto}button{appearance:none;border:0;border-radius:10px;padding:11px 12px;font-size:16px;font-weight:700;background:var(--accent);color:white}button.secondary{background:#e5e5ea;color:#111}button.danger{background:var(--danger)}button:disabled{opacity:.45}.checkline{display:flex;align-items:center;margin:0;font-size:16px;line-height:1.15;white-space:nowrap}.checkline input{width:26px;height:26px;margin:0 8px 0 0;flex:0 0 auto}.signatureDock #status{margin:6px 0 0;font-size:14px}.footer{font-size:13px;color:var(--muted);text-align:center;margin:20px 0 4px}@media(max-width:650px){body{font-size:17px;padding-left:12px;padding-right:12px;padding-bottom:390px}.patient{grid-template-columns:1fr}.top{display:block}.ver{text-align:left;margin-top:4px}.signatureDock{left:6px;right:6px;padding:8px}.checkline+.checkline{margin-left:14px}.checkline{font-size:13px}.checkline input{width:23px;height:23px;margin-right:6px}.sigbox canvas{height:185px}.btns{grid-template-columns:1fr 1.6fr 1fr}button{font-size:14px;padding:10px 8px}}
.warningNotice{border:2px solid var(--danger);border-radius:12px;background:#fff3f2;color:var(--danger);font-weight:800;padding:12px;margin-bottom:14px}
.checkline input{margin:0}.checkText{display:inline-block;padding-left:8px}.checkline.smsConsentLine{margin-left:0;padding-left:28px}
@media(max-width:650px){.checkText{padding-left:6px}.checkline.smsConsentLine{margin-left:0;padding-left:18px}}
</style>
</head>
<body>
<div class="wrap">
  <div class="top">
    <div class="brand"><?php echo h($UI_TITLE); ?></div>
    <div class="ver"><?php echo h($APP_VERSION); ?></div>
  </div>

<?php if (!$hasRequest): ?>
  <div class="card">
    <h1>Warte auf Auftrags-GDT</h1>
    <p>Ordner: <code><?php echo h($dirGdt); ?></code></p>
    <p>Erwarteter Dateiname: <code><?php echo h($REQUEST_GDT_NAME); ?></code></p>
    <p class="muted">Seite aktualisiert sich automatisch alle 3 Sekunden.</p>
  </div>
  <script>setTimeout(function(){ window.location.reload(); },3000);</script>
<?php else: ?>
  <div class="card">
    <h1><?php echo h($docHeading); ?></h1>
    <div class="patient">
      <div class="muted">Patient</div><div><b><?php echo h($displayName_ui); ?></b></div>
      <div class="muted">Geburtsdatum</div><div><?php echo h($gebdat_ui); ?></div>
      <div class="muted">Patientennummer</div><div><?php echo h(req_to_utf8_for_ui($patientNoForFileRaw)); ?></div>
    </div>
  </div>

  <?php if ($yamlError !== null): ?>
    <div class="card err">YAML-Fehler: <?php echo h((string)$yamlError); ?></div>
  <?php else: ?>
    <form id="dsgvoForm" class="card" method="post">
      <?php if ($noticeBanner !== ''): ?>
        <div class="warningNotice"><?php echo h($noticeBanner); ?></div>
      <?php endif; ?>
      <div class="doc-text">
        <?php foreach (yaml_text_blocks($yaml) as $block): ?>
          <?php if ($block['type'] === 'heading'): ?>
            <h2><?php echo h((string)$block['text']); ?></h2>
          <?php elseif ($block['type'] === 'section_title'): ?>
            <h2><?php echo h((string)$block['text']); ?></h2>
          <?php else: ?>
            <p><?php echo nl2br(h((string)$block['text'])); ?></p>
          <?php endif; ?>
        <?php endforeach; ?>
      </div>

      <div class="signatureDock">
        <div class="consentLines">
          <label class="checkline" for="emailConsent">
            <input id="emailConsent" type="checkbox" name="email_consent" value="yes">
            <span class="checkText"><?php echo h($checkboxLabel); ?></span>
          </label>
          <label class="checkline smsConsentLine" for="smsConsent">
            <input id="smsConsent" type="checkbox" name="sms_consent" value="yes">
            <span class="checkText"><?php echo h($smsCheckboxLabel); ?></span>
          </label>
        </div>
        <h2>Unterschrift</h2>
        <div class="sigbox"><canvas id="sigCanvas"></canvas></div>
        <input type="hidden" name="signature_data" id="signatureData" value="">
        <div class="btns">
          <button type="button" class="secondary" id="clearSig">Unterschrift loeschen</button>
          <button type="submit" id="submitBtn"><?php echo h($submitLabel); ?></button>
          <button type="button" class="danger" id="abortBtn">❌ Abbruch</button>
        </div>
        <p id="status" class="muted"></p>
      </div>
    </form>
  <?php endif; ?>
<?php endif; ?>

  <div class="footer"><?php echo h($APP_FOOTER); ?></div>
</div>

<script>
(function(){
  var RETURN_TO = <?php echo json_encode($RETURN_TO, JSON_UNESCAPED_SLASHES); ?>;
  var canvas = document.getElementById('sigCanvas');
  if (!canvas) return;
  var ctx = canvas.getContext('2d');
  var drawing = false;
  var signed = false;
  function resize(){
    var ratio = Math.max(window.devicePixelRatio || 1, 1);
    var rect = canvas.getBoundingClientRect();
    canvas.width = Math.round(rect.width * ratio);
    canvas.height = Math.round(rect.height * ratio);
    if (ctx.setTransform) ctx.setTransform(ratio,0,0,ratio,0,0);
    else ctx.scale(ratio,ratio);
    ctx.lineWidth = 2.5;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = '#111';
  }
  function pos(ev){
    var point = ev;
    if (ev.touches && ev.touches.length) point = ev.touches[0];
    else if (ev.changedTouches && ev.changedTouches.length) point = ev.changedTouches[0];
    var r = canvas.getBoundingClientRect();
    return {x: point.clientX - r.left, y: point.clientY - r.top};
  }
  function stopDefault(ev){ if (ev && ev.preventDefault) ev.preventDefault(); }
  function start(ev){ drawing = true; signed = true; var p = pos(ev); ctx.beginPath(); ctx.moveTo(p.x,p.y); stopDefault(ev); }
  function move(ev){ if(!drawing) return; var p = pos(ev); ctx.lineTo(p.x,p.y); ctx.stroke(); stopDefault(ev); }
  function end(ev){ if (!drawing) return; drawing = false; stopDefault(ev); }
  resize();
  if (window.PointerEvent) {
    canvas.addEventListener('pointerdown', start, false);
    canvas.addEventListener('pointermove', move, false);
    canvas.addEventListener('pointerup', end, false);
    canvas.addEventListener('pointercancel', end, false);
    canvas.addEventListener('pointerleave', end, false);
  } else {
    canvas.addEventListener('touchstart', start, false);
    canvas.addEventListener('touchmove', move, false);
    canvas.addEventListener('touchend', end, false);
    canvas.addEventListener('touchcancel', end, false);
    canvas.addEventListener('mousedown', start, false);
    canvas.addEventListener('mousemove', move, false);
    canvas.addEventListener('mouseup', end, false);
    canvas.addEventListener('mouseleave', end, false);
  }

  var clearBtn = document.getElementById('clearSig');
  if (clearBtn) clearBtn.addEventListener('click', function(){ resize(); signed=false; document.getElementById('signatureData').value=''; }, false);

  var form = document.getElementById('dsgvoForm');
  var status = document.getElementById('status');
  var submitBtn = document.getElementById('submitBtn');

  function sendForm(formData, done){
    var xhr = new XMLHttpRequest();
    xhr.open('POST', window.location.href, true);
    xhr.setRequestHeader('Cache-Control', 'no-store');
    xhr.onreadystatechange = function(){
      if (xhr.readyState !== 4) return;
      var data = {};
      try { data = JSON.parse(xhr.responseText || '{}'); } catch (ignore) {}
      done(xhr.status >= 200 && xhr.status < 300, data);
    };
    xhr.onerror = function(){ done(false, {message:'Netzwerkfehler'}); };
    xhr.send(formData);
  }

  if (form) form.addEventListener('submit', function(ev){
    ev.preventDefault();
    if (form.checkValidity && !form.checkValidity()) {
      if (form.reportValidity) form.reportValidity();
      return;
    }
    if (!signed) { alert('Bitte unterschreiben.'); return; }
    document.getElementById('signatureData').value = canvas.toDataURL('image/png');
    submitBtn.disabled = true;
    status.textContent = 'Wird gespeichert ...';
    sendForm(new FormData(form), function(ok, data){
      if (!ok || data.status !== 'ok') {
        status.className = 'err';
        status.textContent = 'Fehler: ' + (data.message || 'Uebertragung fehlgeschlagen');
        submitBtn.disabled = false;
        return;
      }
      status.className = 'ok';
      status.textContent = 'Fertig. PDF: ' + data.pdf + ' | GDT: ' + data.answer_gdt;
      setTimeout(function(){ window.location.href = RETURN_TO; }, 1200);
    });
  }, false);

  var abortBtn = document.getElementById('abortBtn');
  if (abortBtn) abortBtn.addEventListener('click', function(){
    if (!confirm('Auftrag abbrechen und <?php echo h($REQUEST_GDT_NAME); ?> loeschen?')) return;
    var fd = new FormData();
    fd.append('action','abort');
    sendForm(fd, function(ok, data){
      alert(data.message || 'abgebrochen');
      window.location.href = RETURN_TO;
    });
  }, false);
})();
</script>
</body>
</html>
