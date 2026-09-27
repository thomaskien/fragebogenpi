<?php
declare(strict_types=1);

// Echte GET/POST-Ausfuehrung in separaten PHP-Prozessen; ausschliesslich synthetische GDTs.
// JSON ist eine YAML-Teilmenge. Der Testparser ersetzt nur die lokal optionale YAML-Extension.
$source = file_get_contents(__DIR__ . '/../tablet.php');
$base = sys_get_temp_dir() . '/fragebogenpi-chain-test-' . bin2hex(random_bytes(6));
mkdir($base, 0700);
$checks = 0;
function check(bool $ok, string $message): void {
    global $checks;
    $checks++;
    if (!$ok) throw new RuntimeException($message);
}
function remove_tree(string $path): void {
    if (is_dir($path) && !is_link($path)) {
        foreach (scandir($path) as $name) if ($name !== '.' && $name !== '..') remove_tree($path . '/' . $name);
        rmdir($path);
    } elseif (file_exists($path) || is_link($path)) unlink($path);
}
function fixture(string $label, array $follow = [], bool $handler = false): array {
    $form = ['meta' => ['title' => $label], 'ui' => ['show_contact_section' => false], 'sections' => [
        ['title' => $label, 'questions' => [['id' => 'value', 'label' => $label . '-Antwort', 'type' => 'choice', 'required' => true, 'options' => ['Ja', 'Nein']]]]
    ]];
    if ($handler) $form['meta']['handler'] = 'datenschutz.php';
    $form['follow_up_forms'] = array_map(fn($id) => ['form' => $id, 'when' => ['id' => 'value', 'equals' => 'Ja']], $follow);
    return $form;
}
function setup_case(string $name, array $forms): string {
    global $base, $source;
    $dir = $base . '/' . $name;
    mkdir($dir); mkdir($dir . '/gdt'); mkdir($dir . '/forms');
    foreach ($forms as $id => $form) file_put_contents($dir . '/forms/' . $id . '.yaml', json_encode($form));
    $code = str_replace("\$dirGdt = '/srv/fragebogenpi/GDT';", '$dirGdt = ' . var_export($dir . '/gdt', true) . ';', $source);
    $code = str_replace("\$FORM_DIR = '/srv/fragebogenpi/formulare';", '$FORM_DIR = ' . var_export($dir . '/forms', true) . ';', $code);
    $code = str_replace("'/etc/fragebogenpi/tablet-count'", var_export($dir . '/tablet-count', true), $code);
    file_put_contents($dir . '/tablet.php', $code);
    file_put_contents($dir . '/runner.php', <<<'RUNNER'
<?php
if (!function_exists('yaml_parse_file')) {
    function yaml_parse_file($path) { return json_decode(file_get_contents($path), true); }
}
$args = json_decode(stream_get_contents(STDIN), true);
$_SERVER['SCRIPT_NAME'] = $args['script'];
$_SERVER['REQUEST_METHOD'] = $args['method'];
$_POST = $args['post'];
register_shutdown_function(function () { fwrite(STDERR, 'HTTP:' . (http_response_code() ?: 200)); });
require __DIR__ . '/tablet.php';
RUNNER);
    return $dir;
}
function field(string $id, string $value): string { return sprintf('%03d', strlen($value) + 9) . $id . $value . "\r\n"; }
function request(string $dir, string $name, string $patient = 'TEST-001', bool $legacyId = false): void {
    $raw = field('8000', '6302') . field($legacyId ? '0193' : '3000', $patient) . field('3101', "M\x81ller")
        . field('3102', 'Test') . field('3103', '01011980') . field('8315', 'PVS_TEST') . field('8316', 'ROOT_TEST')
        . field('8402', 'ALLG0') . field('4104', '101112') . field('4109', '20260927');
    file_put_contents($dir . '/gdt/' . $name, $raw);
}
function call_page(string $dir, string $method = 'GET', array $post = [], string $tablet = ''): array {
    $pipes = [];
    $process = proc_open([PHP_BINARY, '-d', 'display_errors=stderr', $dir . '/runner.php'], [['pipe','r'], ['pipe','w'], ['pipe','w']], $pipes);
    fwrite($pipes[0], json_encode(['method'=>$method, 'post'=>$post, 'script'=>'/tablet' . $tablet . '.php'])); fclose($pipes[0]);
    $output = stream_get_contents($pipes[1]); fclose($pipes[1]);
    $errors = stream_get_contents($pipes[2]); fclose($pipes[2]);
    $exit = proc_close($process);
    check($exit === 0, 'PHP-Prozess gescheitert: ' . $errors);
    check(preg_match('/^HTTP:(\d+)$/', $errors, $match) === 1, 'PHP-Warnung/Fehler: ' . $errors);
    return ['body'=>$output, 'code'=>(int)$match[1], 'json'=>json_decode($output, true)];
}
function page_fields(array $response): array {
    $fields = [];
    foreach (['request_gdt', 'chain_token', 'form_id'] as $name) {
        check(preg_match('/name="' . $name . '" value="([^"]*)"/', $response['body'], $match) === 1, 'Fehlendes Feld: ' . $name . ' / ' . substr($response['body'], 0, 200));
        $fields[$name] = html_entity_decode($match[1], ENT_QUOTES, 'UTF-8');
    }
    return $fields;
}
function submit(string $dir, array $fields, string $tablet = '', array $extra = []): array {
    return call_page($dir, 'POST', array_replace($fields, ['q'=>['value'=>'Ja']], $extra), $tablet);
}
function outputs(string $dir): array { return array_map('basename', glob($dir . '/gdt/*-o.gdt')); }
function valid_gdt(string $path): string {
    $raw = file_get_contents($path);
    check(str_ends_with($raw, "\r\n"), 'CRLF-Abschluss');
    check(!preg_match('/(?<!\r)\n/', $raw), 'Nur CRLF');
    foreach (explode("\r\n", rtrim($raw, "\r\n")) as $line) {
        check((int)substr($line, 0, 3) === strlen($line) + 2, 'GDT-Zeilenlaenge');
        if (substr($line, 3, 4) === '8100') check((int)substr($line, 7) === strlen($raw), 'GDT-Gesamtlaenge');
    }
    return $raw;
}
try {
    $dir = setup_case('folge', ['ana'=>fixture('Anamnese',['isi','phq9']), '5-isi'=>fixture('ISI'), '10-phq9'=>fixture('PHQ9')]);
    request($dir,'ana-i.gdt');
    $first = page_fields(call_page($dir));
    check($first['form_id'] === 'ana', 'Startbogen');
    $r = submit($dir,$first,'',['height_cm'=>'180','phone1'=>'0123']);
    check($r['json']['chain_pending'] === true && outputs($dir) === [], 'Keine Zwischenantwort');
    check(!file_exists($dir.'/gdt/isi-i.gdt') && !file_exists($dir.'/gdt/phq9-i.gdt'), 'Keine externen Folgeauftraege');
    check(submit($dir,$first)['code'] === 409, 'Doppel-POST zurueckgewiesen');
    $next = page_fields(call_page($dir));
    check($next['form_id'] === 'isi' && $next['request_gdt'] === 'ana-i.gdt', 'Prioritaet/Root-Zuordnung');
    check(page_fields(call_page($dir)) === $next, 'Reload behaelt Schritt');
    check(submit($dir,$next)['json']['chain_pending'] === true && outputs($dir) === [], 'Noch keine finale Antwort');
    $last = page_fields(call_page($dir));
    check($last['form_id'] === 'phq9', 'Zweiter Folgefragebogen');
    check(submit($dir,$last,'',['email'=>'test@example.invalid'])['json']['answer_gdt'] === 'ana-o.gdt', 'Gemeinsame Antwort');
    check(outputs($dir) === ['ana-o.gdt'], 'Genau eine Ausgabe');
    $raw = valid_gdt($dir.'/gdt/ana-o.gdt');
    foreach (['Anamnese-Antwort: Ja', 'ISI-Antwort: Ja', 'PHQ9-Antwort: Ja', '3000TEST-001', "3101M\x81ller", '8315ROOT_TEST', '8316PVS_TEST', '3622180', '36260123', '3619test@example.invalid'] as $text) check(str_contains($raw,$text),'Ergebnis/Metadata fehlt: '.$text);
    check(!file_exists($dir.'/gdt/ana-i.gdt') && glob($dir.'/gdt/.fragebogenpi-chain-*') === [], 'Auftrag/Fortschritt bereinigt');

    $dir=setup_case('gleichzeitig',['ana'=>fixture('Anamnese',['isi']), 'isi'=>fixture('ISI')]); request($dir,'ana-i.gdt');
    $fields=page_fields(call_page($dir)); $processes=[];
    for($i=0;$i<2;$i++) {
        $pipes=[];
        $process=proc_open([PHP_BINARY,'-d','display_errors=stderr',$dir.'/runner.php'],[['pipe','r'],['pipe','w'],['pipe','w']],$pipes);
        fwrite($pipes[0],json_encode(['method'=>'POST','post'=>$fields+['q'=>['value'=>'Ja']],'script'=>'/tablet.php'])); fclose($pipes[0]);
        $processes[]=[$process,$pipes];
    }
    $codes=[];
    foreach($processes as [$process,$pipes]) {
        $body=stream_get_contents($pipes[1]); fclose($pipes[1]); $err=stream_get_contents($pipes[2]); fclose($pipes[2]);
        check(proc_close($process)===0&&preg_match('/^HTTP:(\d+)$/',$err,$match)===1,'Paralleler Prozess fehlerfrei');
        $codes[]=(int)$match[1];
    }
    sort($codes); check($codes===[200,409],'Parallele Doppeluebermittlung genau einmal verarbeitet');
    $state=json_decode(file_get_contents($dir.'/gdt/.fragebogenpi-chain-ana-i.gdt.json'),true);
    check(count($state['parts'])===1,'Nur ein Ergebnisblock gespeichert');

    $dir = setup_case('einzel', ['isi'=>fixture('ISI')]); request($dir,'isi-i.gdt','LEGACY',true);
    $fields = page_fields(call_page($dir)); check(submit($dir,$fields)['json']['answer_gdt'] === 'isi-o.gdt','Einzel-ISI');
    $raw=valid_gdt($dir.'/gdt/isi-o.gdt'); check(str_contains($raw,'0193LEGACY')&&!str_contains($raw,'3000'),'0193 erhalten');

    $dir = setup_case('verzweigung', ['ana'=>fixture('Anamnese',['isi','phq9']), 'isi'=>fixture('ISI',['cat','ana']), 'phq9'=>fixture('PHQ9',['cat']), 'cat'=>fixture('CAT')]);
    $ana=json_decode(file_get_contents($dir.'/forms/ana.yaml'),true); $ana['meta']['form_ids']=['ana','anam']; file_put_contents($dir.'/forms/ana.yaml',json_encode($ana));
    // Exakter Dateiname im Fixture fuer Hosts ohne native YAML-Extension und fuer Alias-Rueckgabename.
    copy($dir.'/forms/ana.yaml',$dir.'/forms/anam.yaml'); request($dir,'anam-i.gdt');
    $seen=[];
    for($i=0;$i<8;$i++) {
        $fields=page_fields(call_page($dir)); $seen[]=$fields['form_id']; $r=submit($dir,$fields);
        check($r['code']===200,'Verzweigung speichern'); if(!$r['json']['chain_pending']) break;
    }
    check(count($seen)===5 && count(array_filter($seen,fn($id)=>$id==='cat'))===1, 'Dedup und Zyklus beendet');
    check(outputs($dir)===['anam-o.gdt'],'Root-Alias bleibt erhalten');

    $dir=setup_case('tablets',['ana'=>fixture('Anamnese',['isi']), 'isi'=>fixture('ISI')]);
    request($dir,'1-ana-i.gdt','PATIENT-A'); request($dir,'2-isi-i.gdt','PATIENT-B');
    $a=page_fields(call_page($dir,'GET',[],'1')); $b=page_fields(call_page($dir,'GET',[],'2'));
    submit($dir,$a,'1'); submit($dir,$b,'2'); submit($dir,page_fields(call_page($dir,'GET',[],'1')),'1');
    check(outputs($dir)===['1-ana-o.gdt','2-isi-o.gdt'],'Tablet-Ausgaben');
    check(!str_contains(file_get_contents($dir.'/gdt/1-ana-o.gdt'),'PATIENT-B'),'Keine Vermischung');

    $dir=setup_case('separate-roots',['ana'=>fixture('Anamnese',['isi']), 'isi'=>fixture('ISI')]);
    request($dir,'ana-i.gdt'); request($dir,'isi-i.gdt');
    submit($dir,page_fields(call_page($dir))); submit($dir,page_fields(call_page($dir)));
    check(file_exists($dir.'/gdt/isi-i.gdt')&&!file_exists($dir.'/gdt/isi-o.gdt'),'Separater ISI bleibt offen');
    submit($dir,page_fields(call_page($dir))); check(outputs($dir)===['ana-o.gdt','isi-o.gdt'],'Separate Auftraege desselben Patienten');

    $dir=setup_case('abbruch',['ana'=>fixture('Anamnese',['isi','phq9']), 'isi'=>fixture('ISI'), 'phq9'=>fixture('PHQ9')]); request($dir,'ana-i.gdt');
    submit($dir,page_fields(call_page($dir))); $fields=page_fields(call_page($dir));
    $r=submit($dir,$fields,'',['action'=>'abort']); check($r['json']['chain_pending']===true,'Abbruch behaelt weitere Boegen');
    submit($dir,page_fields(call_page($dir))); $raw=valid_gdt($dir.'/gdt/ana-o.gdt');
    check(str_contains($raw,'Anamnese-Antwort')&&str_contains($raw,'ISI')&&str_contains($raw,'nicht ausgefuellt')&&str_contains($raw,'PHQ9-Antwort'),'Teilresultate/Abbruchhinweis');
    $dir=setup_case('abbruch-start',['isi'=>fixture('ISI')]); request($dir,'isi-i.gdt');
    submit($dir,page_fields(call_page($dir)),'',['action'=>'abort']); check(outputs($dir)===[]&&!file_exists($dir.'/gdt/isi-i.gdt'),'Startabbruch ohne leere Antwort');

    $dir=setup_case('belegte-antwort',['isi'=>fixture('ISI')]); request($dir,'isi-i.gdt'); file_put_contents($dir.'/gdt/isi-o.gdt','ALT');
    $fields=page_fields(call_page($dir)); $r=submit($dir,$fields);
    check($r['code']===500 && file_get_contents($dir.'/gdt/isi-o.gdt')==='ALT','Kein Ueberschreiben');
    check(file_exists($dir.'/gdt/isi-i.gdt')&&file_exists($dir.'/gdt/.fragebogenpi-chain-isi-i.gdt.json'),'Fortschritt bei Fehler erhalten');
    unlink($dir.'/gdt/isi-o.gdt'); $r=submit($dir,$fields); check($r['code']===200,'Sichere Wiederholung'); valid_gdt($dir.'/gdt/isi-o.gdt');

    $dir=setup_case('schreibfehler',['isi'=>fixture('ISI')]); request($dir,'isi-i.gdt'); $fields=page_fields(call_page($dir));
    mkdir($dir.'/gdt/.fragebogenpi-chain-isi-i.gdt.json.answer');
    $r=submit($dir,$fields); check($r['code']===500&&outputs($dir)===[],'Spool-Schreibfehler');
    rmdir($dir.'/gdt/.fragebogenpi-chain-isi-i.gdt.json.answer');
    check(call_page($dir)['code']===303&&outputs($dir)===['isi-o.gdt'],'Nach Fehler per Reload fortsetzen');

    $dir=setup_case('ersetzt',['ana'=>fixture('Anamnese',['isi']), 'isi'=>fixture('ISI')]); request($dir,'ana-i.gdt','ALT');
    submit($dir,page_fields(call_page($dir))); $fields=page_fields(call_page($dir)); request($dir,'ana-i.gdt','NEU');
    check(submit($dir,$fields)['code']===409&&outputs($dir)===[],'Anderen Patienten ablehnen');
    check(str_contains(call_page($dir)['body'],'ersetzt'),'Konflikt nach Reload sichtbar');

    $dir=setup_case('handler',['ana'=>fixture('Anamnese',['dsgv']), 'dsgv'=>fixture('Datenschutz',[],true)]); request($dir,'ana-i.gdt');
    $fields=page_fields(call_page($dir)); $r=submit($dir,$fields); check($r['code']===500&&outputs($dir)===[],'Handler als Folge klar abgelehnt');
    check(page_fields(call_page($dir))===$fields,'Handlerfehler behaelt Startbogen');
    unlink($dir.'/gdt/ana-i.gdt'); request($dir,'dsgv-i.gdt'); check(call_page($dir)['code']===302,'Separater Handler weiterhin weitergeleitet');

    $dir=setup_case('patientenkonflikt',['ana'=>fixture('Anamnese',['isi']), 'isi'=>fixture('ISI')]); request($dir,'ana-i.gdt','A');
    submit($dir,page_fields(call_page($dir))); request($dir,'isi-i.gdt','B');
    $page=call_page($dir); check(str_contains($page['body'],'Zuordnungsfehler'),'Patientenkonflikt sichtbar');
    check(file_exists($dir.'/gdt/ana-i.gdt')&&file_exists($dir.'/gdt/isi-i.gdt')&&outputs($dir)===[],'Konflikt loescht keine Auftraege');

    $dir=setup_case('fehlendes-yaml',['ana'=>fixture('Anamnese',['isi'])]); request($dir,'ana-i.gdt');
    $fields=page_fields(call_page($dir)); check(submit($dir,$fields)['code']===500&&outputs($dir)===[],'Fehlendes Folge-YAML');
    file_put_contents($dir.'/forms/isi.yaml',json_encode(fixture('ISI'))); check(submit($dir,$fields)['json']['chain_pending']===true,'Nach Konfigurationskorrektur fortsetzen');

    $dir=setup_case('kontakt-folge',['ana'=>fixture('Anamnese',['isi']), 'isi'=>fixture('ISI')]);
    $isi=json_decode(file_get_contents($dir.'/forms/isi.yaml'),true); $isi['ui']['show_contact_section']=true;
    file_put_contents($dir.'/forms/isi.yaml',json_encode($isi)); request($dir,'ana-i.gdt');
    submit($dir,page_fields(call_page($dir)),'',['phone1'=>'NEU-123']);
    $page=call_page($dir); check(str_contains($page['body'],'value="NEU-123"'),'Aktualisierter Kontakt im Folgeformular');
    submit($dir,page_fields($page),'',['phone1'=>'NEU-123']);
    check(str_contains(file_get_contents($dir.'/gdt/ana-o.gdt'),'3626NEU-123'),'Kontaktaenderung bleibt erhalten');

    $dir=setup_case('korrupter-fortschritt',['isi'=>fixture('ISI')]); request($dir,'isi-i.gdt'); $fields=page_fields(call_page($dir));
    file_put_contents($dir.'/gdt/.fragebogenpi-chain-isi-i.gdt.json','{ungueltig');
    check(submit($dir,$fields)['code']===409&&outputs($dir)===[],'Korrupter Fortschritt wird nicht ueberschrieben');

    $dir=setup_case('publikationsabbruch',['isi'=>fixture('ISI')]); request($dir,'isi-i.gdt');
    $fields=page_fields(call_page($dir)); file_put_contents($dir.'/gdt/isi-o.gdt','ALT'); submit($dir,$fields);
    $path=$dir.'/gdt/.fragebogenpi-chain-isi-i.gdt.json'; $state=json_decode(file_get_contents($path),true);
    $state['phase']='publishing'; file_put_contents($path,json_encode($state)); unlink($dir.'/gdt/isi-o.gdt');
    check(submit($dir,$fields)['code']===409&&outputs($dir)===[],'Unklarer Importstatus erzeugt keine doppelte Antwort');
    check(file_exists($path),'Antworten bei unklarem Importstatus erhalten');

    if (isset($argv[1])) {
        $real=json_decode(file_get_contents($argv[1]),true,512,JSON_THROW_ON_ERROR);
        $dir=setup_case('echte-formulare',$real); request($dir,'ana-i.gdt');
        $page=page_fields(call_page($dir));
        $r=submit($dir,$page,'',['q'=>['schlafstoerung'=>'1']]);
        check($r['json']['chain_pending']===true&&outputs($dir)===[],'Echte Anamnese startet ISI');
        $page=call_page($dir); check(str_contains($page['body'],'letzten 4 Wochen'),'Bezugszeitraum im echten Formular sichtbar');
        $fields=page_fields($page); check($fields['form_id']==='isi','Echter ISI ausgewaehlt');
        $answers=[];
        foreach($real['isi']['sections'] as $section) foreach($section['questions'] as $q) {
            if(($q['type']??'')==='choice') $answers[$q['id']]=end($q['options']);
        }
        check(submit($dir,$fields,'',['q'=>$answers])['json']['answer_gdt']==='ana-o.gdt','Echter ISI in gemeinsamer Antwort');
        $raw=valid_gdt($dir.'/gdt/ana-o.gdt');
        check(str_contains($raw,'28/28 Punkte')&&str_contains($raw,'Schwere Schlaflosigkeit')&&str_contains($raw,'Schlafstoerung'),'Echte Auswertung/Anamnese vollstaendig');
    }

    echo "OK: $checks Pruefungen; echte GET/POST-Prozesse, Folgen/Einzelauftraege, GDT, Persistenz, Tablets, Abbruch, Konflikte und Fehlerwiederholung.\n";
} finally {
    remove_tree($base);
}
