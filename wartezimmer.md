# fragebogenpi Wartezimmerbildschirm – Spezifikation v1.5.8

Stand: 2026-09-29

## Zweck

Ein separater Raspberry Pi zeigt im Wartezimmer lokale Videos oder Bilder im
Kioskmodus. Wenn ein Patientenaufruf vom zentralen fragebogenpi eintrifft, wird
die Medienwiedergabe unterbrochen und der datensparsame Aufruf für die
konfigurierte Dauer eingeblendet.

Die vollständige GDT-Datei bleibt dabei auf dem zentralen fragebogenpi und wird
niemals an den Wartezimmer-Pi übertragen.

## Systemarchitektur

### Zentraler fragebogenpi 1.7.1

- Die Praxissoftware schreibt Auftragsdateien über LAN/SMB in den separaten
  Share:

  ```text
  \\fragebogenpi\wartezimmer-GDT
  -> /srv/fragebogenpi/wartezimmer-GDT
  ```

- Samba bleibt ausschließlich über `eth0` erreichbar.
- Die GDT-Dateien liegen außerhalb des WLAN-Webroots.
- Im WLAN-Webroot stellt `wartezimmer-server.php` die einzige
  Wartezimmer-Schnittstelle bereit.
- Die Datenschutzkonfiguration liegt außerhalb von Webroot und Samba-Share:

  ```text
  /etc/fragebogenpi/wartezimmer-config.php
  ```

### Wartezimmer-Pi 1.5.8

- Apache/PHP liefert die lokale Kiosk-Web-App `wartezimmer.php` aus.
- Ein lokales Python-Backend fragt ausschließlich folgenden Endpunkt ab:

  ```text
  http://10.23.0.1/wartezimmer-server.php
  ```

- Das Backend veröffentlicht empfangene Aufrufe lokal per SSE:

  ```text
  http://127.0.0.1:8765/events
  ```

- Firefox ESR öffnet im Kioskmodus nur:

  ```text
  http://127.0.0.1/wartezimmer.php
  ```

## GDT-Share und Dateinamen

Pro Wartezimmer kann immer nur ein Patient warten. Deshalb bleibt es bei genau
einem festen, von der Praxissoftware bestimmten Dateinamen je Wartezimmer.

Beispiele:

```text
Wartezimmer_1.gdt -> Wartezimmer 1
Wartezimmer_2.gdt -> Wartezimmer 2
```

Der Dateiname ohne Erweiterung bestimmt das Ziel. Unterstriche werden für die
Anzeige durch Leerzeichen ersetzt.

Wenn mehrere Wartezimmer-Dateien vorhanden sind, wird immer die älteste Datei
zuerst verarbeitet. Bei identischer Änderungszeit entscheidet der Dateiname in
alphabetischer Reihenfolge. Pro HTTP-Query wird genau eine Datei ausgegeben und
sofort gelöscht. Danach wird beim nächsten Query die nun älteste Datei
verarbeitet. Es gibt keine Altersgrenze: Auch lange vorhandene Dateien werden
so lange ausgegeben, bis der Share keine GDT-Datei mehr enthält.

Unterverzeichnisse, symbolische Links, versteckte Dateien und Dateien ohne
`.gdt`-Erweiterung werden nicht verarbeitet.

## Datensparsame Namensdarstellung

Aus der GDT-Datei werden ausschließlich folgende Felder gelesen:

- `3102`: Vorname
- `3101`: Nachname

Der fragebogenpi-Installer fragt Vor- und Nachname unabhängig voneinander ab:

1. Soll der Namensteil gekürzt werden?
2. Wenn ja: Wie viele Buchstaben sollen angezeigt werden?
3. Wenn ja: Soll ein Punkt angehängt werden?

Standard:

```text
Vorname:  gekürzt auf 1 Buchstaben, mit Punkt
Nachname: gekürzt auf 2 Buchstaben, mit Punkt

Thomas Kienzle -> T. Ki.
```

Wird ein Namensteil nicht gekürzt, wird er vollständig angezeigt. Es gibt keine
fachliche Obergrenze für die Buchstabenanzahl; geprüft wird nur, ob die Eingabe
als positive ganze Zahl verwendbar ist.

An den Wartezimmer-Pi werden ausschließlich diese Werte übertragen:

```json
{
  "display_text": "T. Ki.",
  "target": "Wartezimmer 1"
}
```

Patienten-ID, Geburtsdatum, vollständiger GDT-Inhalt und ursprünglicher
Dateiname werden nicht übertragen.

## Query- und Löschverhalten

- Der Wartezimmer-Pi verwendet ausschließlich HTTP GET.
- HTTP HEAD dient nur dem nicht konsumierenden Verbindungstest des Installers.
- Ist keine GDT-Datei vorhanden, antwortet der Server mit `204 No Content`.
- Ist eine Datei vorhanden, wird die älteste Datei unter einer kurzen
  Dateisperre gelesen.
- Die minimale JSON-Antwort wird vollständig erzeugt.
- Anschließend wird die GDT-Datei sofort gelöscht und die Antwort mit HTTP 200
  ausgegeben.
- Es gibt kein Bestätigungs- oder Ack-Verfahren.
- Es gibt kein Zugriffstoken.
- Das Backend fragt den fragebogenpi-Server nur ab, während der lokale
  Kiosk-Bildschirm über SSE verbunden ist.
- Der ausschließlich an `127.0.0.1` gebundene SSE-Endpunkt erlaubt dem
  Kiosk-Ursprung `http://127.0.0.1` den Browserzugriff.
- Nach einer Aufrufanzeige wartet das Backend zunächst die vollständige
  Anzeigezeit und anschließend zusätzlich das konfigurierte Query-Intervall ab.

## Installer-Abfragen des Wartezimmer-Pi

Version 1.5.8 fragt interaktiv:

```text
Installation wirklich starten? [y/N]

Hostname [wartezimmer]:

WLAN konfigurieren? [J/n]
WLAN SSID [fragebogenpi]:
WLAN Passwort:
WLAN Passwort (Wiederholung):

IP-Adresse des fragebogenpi-Servers [10.23.0.1]:
Abfrageintervall in Sekunden [3]:

Täglich herunterfahren um HH:MM [nein]:
Zeitzone für das Herunterfahren [Europe/Berlin]:
```

Die eigene WLAN-IP erhält der Wartezimmer-Pi per DHCP vom fragebogenpi. Bei
aktivem NetworkManager wird das tatsächlich erkannte WLAN-Interface verwendet.
Andernfalls wird `wpa_supplicant` konfiguriert. Die Installation bricht mit
einer Gerätediagnose ab, wenn kein WLAN-Interface erkannt wird.

Server-IP und Query-Intervall werden außerhalb des Webroots gespeichert:

```text
/etc/fragebogenpi-wartezimmer/server.json
```

Für das Query-Intervall gibt es keine fachliche Obergrenze; es muss lediglich
eine positive Zahl sein.

Chrony verwendet ausschließlich die eingegebene fragebogenpi-IP als Zeitserver;
öffentliche Fallbacks oder weitere DHCP-Zeitquellen werden nicht konfiguriert.
Der zentrale Pi kündigt seinen NTP-Dienst zusätzlich per DHCPv4-Option 42 an.

Die optionale Abschaltzeit muss zwischen `00:00` und `23:59` liegen. `nein`
oder eine leere Eingabe deaktiviert und entfernt nur den eigenen Abschalttimer.
Die IANA-Zeitzone wird im Timer fest eingetragen, ohne die Systemzeitzone zu
ändern. Vor dem Abschalten prüft der Dienst mit einem einzelnen Chrony-Versuch
die Synchronisation und vergleicht nochmals die aktuelle Ortszeit. Verpasste
Termine werden nicht nachgeholt.
Der Timer wird erst am Ende der Installation aktiviert. Bei erneuter
Installation wird ein vorhandener eigener Timer vorher angehalten.

Technische Referenzen: [Chrony-Konfiguration](https://chrony-project.org/doc/4.6/chrony.conf.html),
[DHCP-Optionen in dnsmasq](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html),
[systemd-Timer](https://github.com/systemd/systemd/blob/main/man/systemd.timer.xml).

## Medien- und Anzeigeverhalten

Die lokale Datei `/var/www/html/wartezimmer.json` enthält ausschließlich die
Anzeige- und Medienkonfiguration:

- `mode`: `video` oder `slideshow`
- `video_random_order`: zufällige Video-Reihenfolge (`true` im Installer)
- `display_seconds`: Dauer des Aufruf-Overlays
- `video_dir`, `image_dir`, `sound_dir`
- `default_sound`
- `slideshow_interval_seconds`
- `playlist_restart_on_call_end`
- Audioeinstellungen für Video- und Aufrufton

Für die Audioausgabe von Firefox installiert der Installer `pipewire-audio`.

Mit `video_random_order: true` wird die Video-Playlist beim Start und nach jedem
vollständigen Durchlauf neu gemischt. Jedes Video kommt pro Durchlauf genau
einmal vor. Bei mehr als einem Video wird eine direkte Wiederholung am Übergang
zwischen zwei Durchläufen vermieden. Aufrufpausen behalten die Reihenfolge bei.
Falls `playlist_restart_on_call_end` aktiviert ist, beginnt nach dem Aufruf
dieselbe gemischte Playlist erneut von vorne.

Mit `video_random_order: false` (oder fehlender Einstellung in einer vorhandenen
Konfiguration) werden Videos alphabetisch abgespielt. Eine geänderte Einstellung
gilt spätestens ab dem nächsten Durchlauf; Neuladen startet sie sofort.
Bilder werden weiterhin alphabetisch abgespielt. Dotfiles, AppleDouble-Dateien,
`.DS_Store`, `Thumbs.db` und `desktop.ini` werden ignoriert. Fehlerhafte
Videos werden übersprungen.

Bei einem Aufruf:

1. pausiert die normale Medienwiedergabe,
2. wird der Video-Ton stummgeschaltet,
3. erscheinen `display_text` und `target`,
4. wird der konfigurierte Aufrufton abgespielt,
5. wird nach `display_seconds` die normale Wiedergabe fortgesetzt.

## Netzwerk und Firewall

- Der Wartezimmer-Pi verbindet sich als WLAN-Client mit dem isolierten
  fragebogenpi-WLAN.
- Der zentrale fragebogenpi ist dort standardmäßig unter `10.23.0.1`
  erreichbar.
- Der Wartezimmer-Pi erhält seine eigene IP per DHCP.
- Eingehende Verbindungen über das erkannte WLAN-Interface des
  Wartezimmer-Pi bleiben blockiert.
- Ausgehende HTTP-Queries zum fragebogenpi sind erlaubt.
- Ausgehende NTP-Anfragen gehen nur an den konfigurierten fragebogenpi-Server.
- `eth0` des Wartezimmer-Pi bleibt für lokale Administration und den
  Medien-Samba-Share offen.
- Es gibt kein Routing zwischen WLAN und LAN.

## Logging

Für die Wartezimmer-Funktion werden keine Anwendungslogs geschrieben:

- kein Backend-Dateilog,
- kein Backend-stdout/stderr-Log,
- kein aiohttp-Zugriffslog,
- kein Apache-Zugriffs- oder Fehlerlog auf dem Wartezimmer-Pi,
- kein Apache-Zugriffslog für `wartezimmer-server.php` auf dem zentralen
  fragebogenpi.

Normale Systemmeldungen der verwendeten Betriebssystemdienste sind nicht Teil
der Wartezimmer-Anwendungsdaten.

## Wichtige Dateien

### Zentraler fragebogenpi

```text
/srv/fragebogenpi/wartezimmer-GDT
/srv/fragebogenpi/webroot-wlan/wartezimmer-server.php
/etc/fragebogenpi/wartezimmer-config.php
/srv/fragebogenpi/.wartezimmer-server.lock
```

### Wartezimmer-Pi

```text
/var/www/html/wartezimmer.php
/var/www/html/wartezimmer.json
/var/www/html/helper/list_media.php
/var/www/html/videos/
/var/www/html/images/
/var/www/html/sounds/
/etc/fragebogenpi-wartezimmer/server.json
/etc/chrony/chrony.conf
/etc/systemd/system/wartezimmer-poweroff.service
/etc/systemd/system/wartezimmer-poweroff.timer
/usr/local/bin/infodisplay-backend.py
/etc/systemd/system/infodisplay-backend.service
/usr/local/bin/wartezimmer_firefox_kiosk.sh
/etc/lightdm/lightdm.conf.d/50-wartezimmer.conf
```

Die früheren Dateien `sprechzimmer1.gdt`, `sprechzimmer2.gdt`,
`loesche-sprechzimmer1.php` und `loesche-sprechzimmer2.php` im lokalen
Wartezimmer-Webroot werden nicht mehr für den Aufrufweg verwendet.
