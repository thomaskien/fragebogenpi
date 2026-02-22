===============================================================================
fragebogenpi wartezimmerbildschirm — AKTUALISIERTE SPEZIFIKATION (Endstand v1.5.1)
==================================================================================

Zweck / Grundidee

* Ein Raspberry Pi zeigt im Normalzustand im Vollbild stumm (oder optional mit Ton) lokale Medien:

  * Standard: Videos (Landschaft etc.) aus einem Verzeichnis.
  * Alternative: Slideshow aus Bildern (alphabetische Reihenfolge, konfigurierbares Intervall).
* Wenn eine “Aufrufanforderung” eintrifft (GDT-Datei pro Sprechzimmer), wird das Normalprogramm für eine definierte Zeit unterbrochen:

  * Es erscheint ein Vollbild-Overlay (“Aufruf”), inklusive Zieltext (z.B. “Bitte ins Sprechzimmer 1”).
  * Zusätzlich wird ein Tonsignal abgespielt (konfigurierbar).
  * Nach Ablauf springt das System zurück in die normale Video-/Slideshow-Wiedergabe.

Systemarchitektur

* Lokaler Webserver (Apache + PHP) liefert die Web-App (wartezimmer.php) aus.
* Eine lokale Backend-Komponente (Python) pollt mehrere Quellen (pro Sprechzimmer) nach GDT-Dateien und erzeugt “Call Events”.
* Die Web-App bezieht Events per SSE (Server-Sent Events) vom lokalen Backend:

  * SSE Endpoint: [http://127.0.0.1:8765/events](http://127.0.0.1:8765/events)
* Der Browser läuft im Kiosk-Modus und öffnet nur die lokale Seite:

  * [http://127.0.0.1/wartezimmer.php](http://127.0.0.1/wartezimmer.php)
* Schreibzugriffe durch PHP sollen minimal sein:

  * PHP dient primär der Auslieferung von Inhalten und Hilfsendpunkten.
  * Löschoperationen passieren auf dem Quellserver über ein externes PHP-Löschskript (per HTTP), nicht auf dem Display-Gerät.

Netzwerk- und Sicherheitsmodell

* Das Gerät wird einmalig konfiguriert, danach soll Betrieb/Änderung über LAN via SMB möglich sein, ohne SSH.
* Samba und SSH sollen nur über LAN erreichbar sein (physisch “anstecken, konfigurieren”).
* WLAN dient primär als isolierter “Fetch”-Weg:

  * Aufrufe werden bevorzugt per HTTP “pull” gefetcht (Display holt die Datei).
  * Dies gilt als sauberste und sicherste Variante, da der Wartezimmerbildschirm über fragebogenpi vollständig vom Praxisnetz abgeschirmt ist.
* Firewall (nftables):

  * eth0 (LAN): offen (keine Einschränkungen).
  * wlan0: inbound blockiert (nur established/related, DHCP, Ping erlaubt).

Datei- und Verzeichnisstruktur (alles im Webroot)

* Alles liegt direkt unter /var/www/html (kein Unterverzeichnis wie “info-display”):

  * /var/www/html/wartezimmer.php                (Web-App)
  * /var/www/html/wartezimmer.json               (Konfiguration)
  * /var/www/html/helper/list_media.php          (Media-Lister)
  * /var/www/html/videos/                        (MP4/M4V)
  * /var/www/html/images/                        (JPG/JPEG/PNG/WEBP)
  * /var/www/html/sounds/                        (MP3 + M4A)
  * /var/www/html/logs/                          (Apache-Logs, optional Backend-Log)
  * /var/www/html/loesche-sprechzimmer1.php      (lokal nur Test/Platzhalter; real per Quellserver)
  * /var/www/html/loesche-sprechzimmer2.php
  * /var/www/html/README_WARTEZIMMER.txt         (Dokumentation)

Zusätzliche Systemdateien (v1.5.1)

* Firefox-Kiosk-Prepare-Script (wird vom Openbox-Autostart genutzt):

  * /usr/local/bin/wartezimmer_firefox_prepare.sh
* systemd Service für Backend:

  * /etc/systemd/system/infodisplay-backend.service
* LightDM Autologin-Konfiguration:

  * /etc/lightdm/lightdm.conf.d/50-wartezimmer.conf
* Openbox Autostart:

  * /home/pi/.config/openbox/autostart

Wichtige Regeln für Media-Dateien

* Medien werden alphabetisch abgespielt/angezeigt.
* Dotfiles und AppleDouble-Dateien müssen ignoriert werden:

  * Filter: .* (damit auch ._*, insbesondere “._001.mp4” von macOS/SMB).
* Ungültige/defekte Videos müssen zur Laufzeit übersprungen werden:

  * Wenn ein Video nicht abspielbar ist, sofort “nächstes Video” versuchen (Self-Heal).

Konfigurationsdatei (wartezimmer.json) — Pflichtfelder und Bedeutung

* Grundfelder:

  * version: Versionsstring der Konfiguration (v1.5.1: "1.5.1").
  * mode: "video" oder "slideshow".
  * display_seconds: Dauer der Aufrufanzeige (Standard: 10 Sekunden).
  * video_dir/image_dir/sound_dir: Verzeichnisnamen relativ zum Webroot (standard: videos/images/sounds).
  * default_sound: Default-Tondatei in sounds/ (Standard: jsbach.m4a).
  * slideshow_interval_seconds: Intervall für Bilderwechsel.
  * playlist_restart_on_call_end: wenn true, startet Playlist nach Call neu, sonst setzt sie fort.

* Kommentar-Felder (gültiges JSON ohne duplicate keys):

  * _comment0.._commentN: Hinweise (kein echtes JSON-Comment, nur Schlüssel/Wert).

* Audio-Block:

  * audio.video_sound_enabled: true/false (Standard: false)

    * false: Video stumm.
    * true: Video hörbar.
  * audio.video_volume: 0..1 (Standard: 0.15)
  * audio.chime_volume: 0..1 (Standard: 1.0)

* Namensformatierung (optional, aus GDT 3102/3101):

  * name_format.enabled: true/false (Standard: false)

    * false: voller Name “Vorname Nachname”.
    * true: Abkürzung.
  * name_format.first_name.enabled / letters / dot

    * Beispiel: letters=1, dot=true -> “T.”
  * name_format.last_name.enabled / letters / dot

    * Beispiel: letters=3, dot=true -> “Kie.”
  * Separator-Regel:

    * Für das Zählen der Buchstaben werden Leerzeichen und Bindestriche ignoriert.
    * Ignorierte Zeichen: space, tab, "-", "–", "—".

* Fetch-Block:

  * fetch.enabled: true/false (Standard: true)
  * fetch.poll_interval_ms: Pollintervall (Standard: 500ms).
  * fetch.max_jobs_per_room_per_cycle: wie viele Jobs pro Room pro Poll-Runde.
  * fetch.rooms: Liste von Sprechzimmern (v1.5.1 Standard: 2 Räume).

    * pro Room:

      * id: interner Identifier (z.B. “sprechzimmer1”)
      * target: Zieltext im Overlay (z.B. “Bitte ins Sprechzimmer 1”)
      * fetch_url: URL zur GDT-Datei (z.B. [http://127.0.0.1/sprechzimmer1.gdt](http://127.0.0.1/sprechzimmer1.gdt))
      * delete_url: URL zum Löschskript (z.B. [http://127.0.0.1/loesche-sprechzimmer1.php](http://127.0.0.1/loesche-sprechzimmer1.php))
      * enabled: true/false
      * optional: sound_override (überschreibt default_sound)

* Logging-Block:

  * logging.enabled: Standard false
  * logging.sink: “file” oder “stdout”
  * logging.level: debug/info/warn/error
  * logging.log_file: Pfad (z.B. /var/www/html/logs/backend.log)
  * Standardziel: Im Normalfall keine Logs schreiben (logging.enabled=false).

Web-App Verhalten (wartezimmer.php)

Normalmodus

* Lädt wartezimmer.json.
* Ermittelt Medienliste über helper/list_media.php:

  * kind=videos / images / sounds.
* Video-Modus:

  * <video> fullscreen, object-fit: cover, autoplay.
  * Video-Sound abhängig von audio.video_sound_enabled + video_volume.
  * Self-Heal:

    * onerror -> nächstes Video
    * ended -> nächstes Video
    * watchdog: wenn “hängt”, retry play() oder skip
    * focus/visibility: bei Rückkehr in Vordergrund erneut versuchen
    * falls Playlist leer ist: retry (bis max. 60s in ensurePlaylist)
* Slideshow-Modus:

  * <img> fullscreen, object-fit: cover.
  * Timer: slideshow_interval_seconds, zyklisch.

Aufrufmodus

* Bei Event vom Backend (SSE):

  * Normalmodus pausieren.
  * Video-Audio “ducken”:

    * Zustand speichern, dann mute=true und volume=0 (auch wenn Video-Sound aktiviert ist).
  * Overlay anzeigen (Vollbild), mit:

    * großem Aufruftext (aus GDT bzw. formatiert)
    * Ziel (target) aus config
    * source_id (Room-ID) als “kleiner Text” möglich
  * Footer erscheint NUR während Overlay:

    * “Dr. Thomas Kienzle · fragebogenpi.de wartezimmerbildschirm · v1.5.1”
  * Chime abspielen (robust):

    * pause + currentTime=0 + volume setzen + src setzen + play()
  * Nach display_seconds:

    * Overlay weg, Footer weg
    * Video-Audio Zustand restore und config erneut anwenden
    * normal weiterlaufen (oder Playlist neu, falls konfiguriert).

Backend Verhalten (Python)

* Lädt wartezimmer.json regelmäßig (für Änderungen).
* Pollt pro enabled Room:

  * fetch_url per HTTP GET:

    * wenn kein Inhalt/204/!=200 -> nichts tun
    * wenn Inhalt -> GDT parsen
* GDT Parsing:

  * Es werden ausschließlich Felder verwendet:

    * 3102 = Vorname
    * 3101 = Nachname
  * Ausgabe-Name:

    * default: “Vorname Nachname” (trim), fallback “Aufruf”
    * optional abgekürzt nach name_format-Regeln (Zählen ohne Leerzeichen/Bindestriche)
* Event-Publish:

  * sendet SSE Event an alle Clients:

    * type="call"
    * display_text (Name oder “Aufruf” fallback)
    * target (Konfig)
    * source_id (Room-ID)
    * sound (default oder override)
    * display_seconds
* Delete:

  * nach erfolgreichem “Job” wird delete_url aufgerufen (HTTP GET)
  * Ziel: Quellverzeichnis enthält keine personenbezogenen Daten nach Verarbeitung.

Samba / Rechte / Bedienkonzept

* Ein Samba Share stellt das gesamte Webroot bereit:

  * smb://<hostname>/webroot  -> /var/www/html
* Share ist Guest-writable, damit Konfiguration und Medien ohne SSH gepflegt werden können.
* Rechtekonzept:

  * webroot gehört einer Gruppe (infodisplay) mit setgid auf Verzeichnissen, damit neue Dateien korrekte Group bekommen.
  * Apache (www-data) ist in Gruppe infodisplay und kann lesen/schreiben (z.B. Logs / Test-Löschskripte).
  * Verzeichnisse: 2775, Dateien: 0664.

Installer / Boot / Kiosk (v1.5.1)

* Basis: Raspberry Pi OS / Debian 13 Lite → Installer installiert Desktop (openbox/lightdm), Apache/PHP, Samba, nftables, Firefox ESR, Backend.
* Autologin in die grafische Sitzung (User pi).
* Openbox autostart:

  * DPMS/Screensaver aus (xset).
  * Wartet auf lokale Endpunkte:

    * wartezimmer.php
    * wartezimmer.json
    * list_media liefert mindestens 1 Video-Datei (.mp4/.m4v)
  * Startet Firefox im Kiosk:

    * firefox-esr -P kiosk --kiosk --no-remote [http://127.0.0.1/wartezimmer.php](http://127.0.0.1/wartezimmer.php)
  * Firefox-Profil muss zwingend ohne Dialoge funktionieren:

    * v1.5.1 erzwingt das über ein Boot-Prepare-Script (siehe nächster Abschnitt).

Firefox-Profilmanagement (v1.5.1, zentraler Unterschied zu alten Versionen)

* Problemklasse: bei frischem Profil kann Firefox einen Profil-Dialog/Manager anzeigen, was im Kiosk nicht akzeptabel ist.
* Lösung v1.5.1: Bei JEDEM Boot vor dem Kiosk-Start werden die notwendigen Schritte ausgeführt:

  * firefox -CreateProfile kiosk (idempotent)
  * profiles.ini wird aus dem verwendeten Profil-Basisverzeichnis gelesen (praxis-erprobt: /home/pi/.config/mozilla/firefox/profiles.ini)
  * Pfad zum Profil “kiosk” wird aus profiles.ini ermittelt
  * user.js im Profil wird geschrieben/überschrieben (Autoplay + weniger Dialoge)
  * permissions.sqlite/content-prefs* werden entfernt (kann Autoplay blocken)
  * danach wird Firefox mit -P kiosk --kiosk --no-remote gestartet
* Das Boot-Prepare-Script ist:

  * /usr/local/bin/wartezimmer_firefox_prepare.sh
* Das Script wird vom Openbox autostart aufgerufen (und übernimmt den Firefox-Start per exec).

Zusätzliche Bootstraps (v1.5.1)

* Sound:

  * jsbach.m4a wird beim Install nach /var/www/html/sounds/jsbach.m4a geladen (fail-fast, retries, atomar; nur wenn fehlend).
  * wartezimmer.json setzt default_sound="jsbach.m4a".
* Beispielvideo:

  * zzz_beispielvideo.mp4 wird beim Install nach /var/www/html/videos/zzz_beispielvideo.mp4 geladen (fail-fast, retries, atomar; nur wenn fehlend).
  * Ziel: nie “leere Playlist” nach Erstinstallation.

Bekannte/zu vermeidende Fehler (Lessons learned, Stand v1.5.1)

* JSON ist strikt: keine Kommentare, keine doppelten Keys; Kommentare nur via _commentN.
* cloud-init user-data: hostname-Patch muss komplette Zeile ersetzen, niemals nur “hostname:” Token.
* Dotfiles (._*, .DS_Store) müssen serverseitig gefiltert werden, sonst hängt Video-Start am ersten “Fake-File”.
* Firefox-Kiosk: Profilmanager-Fenster ist fatal → deshalb Boot-Prepare bei jedem Start.
* Wichtig für Debugging: Backend-Service schreibt standardmäßig keine Logs (StandardOutput/StandardError null; logging.enabled=false). Bei Fehlersuche ggf. logging.enabled=true setzen und log_file verwenden.

Abweichungen gegenüber der alten Chromium-Spezifikation

* Browser ist in v1.5.1 Firefox ESR (nicht Chromium).
* Es gibt keine Chromium-spezifischen Flags/Policies, kein /run user-data-dir für Browserprofile, kein wmctrl/xdotool F5-Reload.
* Die “Boot-Playback-Härtung” erfolgt in v1.5.1 primär durch:

  * Wait-Loop vor Browserstart
  * Boot-Prepare des Firefox-Profils (Autoplay + Permissions reset) vor Browserstart

# Ende der Spezifikation
