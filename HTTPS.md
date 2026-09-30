# Lokales HTTPS für iPads – Installer 1.7.2

Die Einrichtung verwendet eine eigene dauerhafte Root-CA pro Haupt-Pi. Die iPads
benötigen keinen Internetzugang. Der Haupt-Pi benötigt seine vorhandene, per LAN
synchronisierte Chrony-Uhr. Eine iPad-Zeitsynchronisation über DHCP wird nicht
vorausgesetzt. Zielgeräte der Abnahme sind iPadOS 26.7.1 und iPadOS 18.x.

## Bestehende Installation umstellen

Die aktualisierte `fragebogenpi.sh` auf den Haupt-Pi kopieren und starten:

```bash
sudo bash ./fragebogenpi.sh
```

**7) Nur HTTPS / Zertifikate einrichten / aktualisieren** wählen. Es erfolgt
kein Reboot. Tablet-Betrieb (Modus 5) und Zeitserver (Modus 6, seit 1.7.1) müssen
vorhanden sein. Auf Neuinstallationen ist die Funktion Teil der Auswahl
**HTTP+HTTPS**. Der ausdrücklich gewählte reine HTTP-Betrieb bleibt verfügbar;
eine Rückkehr dazu bei Vollkonfiguration deaktiviert den Erneuerungstimer.
Modus 2 aktualisiert weiterhin nur Webdateien und installiert diese Erweiterung
nicht. Der Installer enthält alle neuen Hilfsprogramme selbst; kein zusätzlicher
Download und kein Python-Paket aus PyPI ist erforderlich.

Modus 7 ermittelt die tatsächliche IPv4-Adresse auf `wlan0` und gleicht sie mit
der bestehenden Apache-Konfiguration ab. Er übernimmt den vorhandenen
Apache-Servernamen und ergänzt dessen DNS-SANs (Name und Name.local). Es wird
kein fremder Hostname wie `kienzlebox` pauschal angenommen. Das Zertifikat enthält
die IP ausdrücklich als IP-SAN. IP und Hostname des Pi werden nicht geändert.

Individuelle/unbekannte Apache-Konfigurationen werden vor Änderungen abgelehnt.
Die vorhandene Tablet-Anzahl und alle zugehörigen PHP-Endpunkte werden geprüft.
Bei geänderter IP oder fehlender/schadhafter CA bricht die Erneuerung klar ab;
eine vorhandene Vertrauenswurzel wird nicht automatisch ersetzt.

## Verhalten im Browser

| Aufruf an der angezeigten WLAN-IP | Ergebnis |
| --- | --- |
| HTTP `/`, `/index.html`, beliebige weitere Seiten | Deutsche Zertifikatsanleitung |
| HTTP `/tablet.php`, `/tablet2.php` usw. | Anleitung mit HTTPS-Schaltfläche für genau diesen Endpunkt |
| HTTP `/wartezimmer-server.php` | Unveränderte Wartezimmer-Schnittstelle; weiterhin ohne Zugriffslog |
| HTTP und HTTPS `/ca.crt` | Öffentliches Root-Zertifikat im DER-X.509-Format (`application/x-x509-ca-cert`) |
| HTTPS `/` oder `/index.html`, ein Tablet | Weiterleitung auf `/tablet.php` |
| HTTPS `/` oder `/index.html`, mehrere Tablets | Auswahl von `/tablet1.php` bis `/tabletN.php` |
| HTTPS `/tabletN.php`, APIs und Assets | Direkter Zugriff auf die jeweilige vorhandene Anwendung |

HTTP führt weder die Tablet-Formulare noch deren POST-Verarbeitung aus. Die
Wartezimmer-Schnittstelle ist die ausdrücklich gewollte PHP-Ausnahme. Es gibt
keine automatische HTTP-zu-HTTPS-Weiterleitung, keinen HTTPS-Test per JavaScript
und keine vermeintliche Abfrage des auf dem iPad installierten CA-Vertrauens.
Die HTTPS-Schaltfläche übernimmt keine Query-Parameter aus einer HTTP-Adresse.

Die Tablet-Auswahl liest `/etc/fragebogenpi/tablet-count` bei jedem Aufruf. Damit
wirkt eine spätere Änderung über Modus 5 ohne Neuerstellung der HTTPS-Seiten.
Eine ungültige vorhandene Anzahl führt zu einer verständlichen Fehlermeldung.
Die GDT-Zuordnung und die Formularprogramme werden nicht verändert.

## Einmalige Installation auf jedem iPad

1. Die vom Installer angezeigte HTTP-Adresse in **Safari** öffnen.
2. **CA-Zertifikat herunterladen** wählen und das Laden des Profils erlauben.
3. In **Einstellungen → Profil geladen**, alternativ **Allgemein → VPN &
   Geräteverwaltung**, das Profil **fragebogenpi Root CA** installieren.
4. Unter **Allgemein → Info → Zertifikatsvertrauenseinstellungen** das volle
   Vertrauen für **fragebogenpi Root CA** einschalten.
5. In Safari **Formular über HTTPS öffnen** wählen. Bei mehreren Tablets die
   passende Nummer wählen und deren direkte HTTPS-Adresse als Lesezeichen speichern.

Download und Anleitung bleiben dauerhaft erreichbar. Die tägliche Ausstellung
ändert die Root-CA nicht; daher ist deswegen keine erneute Installation auf dem
iPad notwendig. Nach Gerätezurücksetzung oder Entfernen des Profils muss das
Vertrauen gegebenenfalls erneut eingerichtet werden.

Der Installer gibt den SHA-256-Fingerabdruck der Root-CA aus. Diesen unabhängig
von der ungesicherten HTTP-Seite in der Betriebsdokumentation festhalten:

```bash
sudo openssl x509 -in /etc/ssl/fragebogenpi/ca.crt -noout -fingerprint -sha256
```

Apple erläutert die [manuelle Vertrauensfreigabe](https://support.apple.com/de-de/102390),
die [Zertifikatsanforderungen](https://support.apple.com/en-us/103769) und die
[Ausnahme privater Root-CAs von der 398-Tage-Begrenzung](https://support.apple.com/en-md/102028).
Die tatsächliche Abnahme auf den genannten iPads bleibt erforderlich.

## Zertifikate, Zeit und Berechtigungen

- Root-CA: RSA 4096, SHA-256, kritische `CA:TRUE,pathlen:0`- und
  `keyCertSign,cRLSign`-Erweiterungen. Beginn 365 Tage vor Erstellung, Ende
  50 Kalenderjahre nach Erstellung. Die Gesamtdauer beträgt damit etwa 51 Jahre.
  Eine lange Laufzeit garantiert keine unveränderte Kompatibilität über Jahrzehnte.
- Serverzertifikat: direkte Signatur durch dieselbe Root-CA; RSA mindestens
  2048 Bit, SHA-256, `CA:FALSE`, `serverAuth`, `digitalSignature,keyEncipherment`.
  Ein geeigneter vorhandener RSA-Schlüssel wird weiterverwendet.
- Jeder tägliche Lauf stellt tatsächlich neu aus. `notBefore = T − 365 × 86400`
  und `notAfter = T + 365 × 86400`, mit einer einzigen aktuellen UTC-Referenz T.
  Seriennummern werden unter exklusiver Sperre vor der Ausstellung reserviert;
  Fehlversuche dürfen Lücken hinterlassen.
- Chrony muss synchronisiert sein (maximal eine Sekunde verbleibende Korrektur).
  Ein deutlicher Rücksprung gegenüber der letzten erfolgreichen Ausstellung
  wird abgelehnt. Außerhalb des gleitenden Fensters bleibt eine falsche iPad-Uhr
  ein Problem. Bei dauerhaften Zeitserverfehlern den Fehler beheben.
- CA-Key, Server-Key und Arbeitsdateien liegen außerhalb aller Webroots und
  Samba-Freigaben in einem root-eigenen Verzeichnis mit Modus 0700; Schlüssel
  haben Modus 0600. PHP läuft weiterhin als `www-data` und kann sie nicht lesen.
- Öffentlich wird ausschließlich die DER-Kopie der Root-CA bereitgestellt.

## Installierte und geänderte Dateien

| Pfad auf dem Pi | Zweck |
| --- | --- |
| `/etc/ssl/fragebogenpi/ca.key`, `ca.crt` | Dauerhafte private Root-CA und öffentliches PEM-Zertifikat |
| `/etc/ssl/fragebogenpi/fragebogenpi.key`, `fragebogenpi.crt` | Server-Key und aktives Serverzertifikat |
| `/etc/ssl/fragebogenpi/https.json` | Geprüfte IP, DNS-Namen, Pfade und CA-Fingerabdruck |
| `/etc/ssl/fragebogenpi/serial`, `renew.lock`, `last-success.json` | Seriennummer, gemeinsame Sperre, letzte bestätigte Ausstellung |
| `/etc/ssl/fragebogenpi/pending.*` | Vorbereitete Ausstellung beim Einrichten |
| `/etc/ssl/fragebogenpi/activation-recovery.json` | Temporäres Journal einer noch nicht abgeschlossenen Aktivierung |
| `/etc/ssl/fragebogenpi/ca-backup/` | Unveränderte lokale Erstkopie der CA und ihres Schlüssels |
| `/etc/ssl/fragebogenpi/previous/` | Vorheriges Serverzertifikat und vorherige HTTPS-Konfiguration |
| `/etc/ssl/fragebogenpi/setup-backups/ZEIT-PID/` | Konfigurationssicherung vor Modus-7-Änderungen |
| `/usr/local/sbin/fragebogenpi-https` | Privilegierter Python-/OpenSSL-Helfer |
| `/var/lib/fragebogenpi-https/public/` | `index.html`, `tablets.php` und öffentlicher Download `ca.crt` |
| `/etc/systemd/system/fragebogenpi-https-renew.service` | Signierdienst als root |
| `/etc/systemd/system/fragebogenpi-https-renew.timer` | Täglich 03:17 Uhr, bis zu fünf Minuten Streuung, `Persistent=true` |
| `/etc/fragebogenpi/apache-wlan/apache2.conf` | HTTP-Anleitung, Ausnahme fürs Wartezimmer, HTTPS-Routen und WLAN-Modulladung |
| `/etc/nftables.conf` | In Modus 7 nur zusätzliche, markierte WLAN-Freigabe für TCP/443 |

Modus 7 verändert weder LAN-Apache noch seine gemeinsam verwendete Modulliste.
Fehlende HTTPS-Module werden ausschließlich in der WLAN-Konfiguration geladen.
Es wird keine gesamte nftables-Konfiguration neu geladen oder geleert: Im
laufenden Regelwerk wird nur die eigene 443-Regel ergänzt. Fremde Tabellen und
Regeln bleiben erhalten. Bei fehlgeschlagener Umstellung werden die alte
Apache-/Firewall-Konfiguration und das vorherige Zertifikat wiederhergestellt.

## Timer, manuelle Erneuerung und Logs

```bash
sudo systemctl status fragebogenpi-https-renew.timer --no-pager
sudo systemctl list-timers fragebogenpi-https-renew.timer
sudo systemctl start fragebogenpi-https-renew.service
sudo journalctl -u fragebogenpi-https-renew.service -n 80 --no-pager
sudo chronyc tracking
```

Alternativ direkt (ebenfalls jedes Mal eine wirkliche Neuausstellung):

```bash
sudo /usr/local/sbin/fragebogenpi-https renew
```

Das Zertifikat wird zunächst temporär erzeugt, gegen CA, IP/DNS, Server-Key,
Erweiterungen und exakte Zeitgrenzen geprüft, dann atomar ersetzt. Nach dem
Apache-Konfigurationstest wird nur `fragebogenpi-apache-wlan.service` graceful
neu geladen. Eine neue TLS-Verbindung muss genau das neue Zertifikat liefern.
Die öffentlichen Startseiten und CA-Downloads werden zusätzlich abgefragt.
Produktive Tablet- und Wartezimmer-Endpunkte werden dabei ausdrücklich nicht
aufgerufen: Die Wartezimmer-Abfrage würde eine wartende GDT-Datei abholen.

Schlägt die Prüfung fehl, wird der vorherige Stand wieder eingesetzt. Ein
unvollständiges Aktivierungsjournal wird beim nächsten Lauf zur Wiederherstellung
verwendet. Ein bei der Erstinstallation neu gestarteter Apache wird bei Fehlern
wieder gestoppt. Ein Erneuerungsfehler wird im Journal als fehlgeschlagener Dienst
sichtbar; der bisherige Zertifikatsstand bleibt erhalten. `Persistent=true` holt
einen während ausgeschaltetem Pi verpassten Timerlauf nach, ersetzt aber keine
Fehlerüberwachung. Eine ausgefallene Erneuerung wird spätestens zum nächsten
Tageslauf erneut versucht; nach Fehlerbehebung kann sie manuell gestartet werden.

## Sicherung und Wiederherstellung

Die Kopie unter `ca-backup` schützt nicht vor Ausfall der SD-Karte. Nach der ersten
erfolgreichen Einrichtung das gesamte Verzeichnis `/etc/ssl/fragebogenpi` sowie
die eigene WLAN-Apache-Konfiguration auf einen geschützten externen Datenträger
sichern. Die Sicherung enthält private Schlüssel: nicht in Webroot, PDF-Share,
GDT-Share oder Git ablegen. Zusätzlich die bei Modus 7 ausgegebene
`setup-backups/ZEIT-PID`-Sicherung aufbewahren.

Bei Verlust der aktiven CA-Dateien den Timer stoppen und **dieselbe** `ca.crt`
samt passender `ca.key` aus der Sicherung als root mit Modus 0600 zurückspielen.
Das Verzeichnis bleibt 0700. Auch Server-Key, Konfiguration und Seriennummer
gehören zu einer vollständigen Wiederherstellung. Zuvor sicherstellen, dass kein
Signierlauf aktiv ist; die gemeinsame Datei `renew.lock` kann dafür mit `flock`
exklusiv gesperrt werden. Danach Fingerabdruck mit der Betriebsdokumentation
vergleichen, die manuelle Erneuerung ausführen und den Timer wieder starten.
Keine neue CA erzeugen, um eine fehlende Datei zu „reparieren“.

Für eine Rücknahme der gesamten Modus-7-Umstellung die gesicherten
`apache2.conf`, `nftables.conf` und gegebenenfalls das vorherige Serverzertifikat
verwenden. Vorhandene sonstige Änderungen seit der Sicherung berücksichtigen.
Die aktive, ausschließlich von Modus 7 ergänzte Regel lässt sich anzeigen mit:

```bash
sudo nft -a list chain inet fragebogenpi input
```

Nur die Regel mit dem Kommentar `fragebogenpi-https` und ihrem aktuellen Handle
gezielt entfernen; keine fremden Regeln löschen und kein globales `flush ruleset`
ausführen. WLAN-Apache anschließend mit den in seiner systemd-Unit gesetzten
Apache-Laufzeitvariablen prüfen und neu laden. Der automatische Fehler-Rollback
erledigt diese Schritte für Fehler während einer normalen Modus-7-Ausführung.

## Tests und Abnahme

Automatisiert ohne Patientendaten und ohne Systemdienständerungen:

```bash
bash -n fragebogenpi.sh
python3 tests/https_certificates_test.py
python3 tests/https_pages_test.py
python3 tests/https_installer_test.py
python3 tests/installer_time_test.py
php tests/tablet_form_chains_test.php
```

Zusätzlicher echter Apache-/PHP-/TLS-Integrationstest, benötigt Apache 2.4,
PHP-CGI und freie hohe Loopback-Ports:

```bash
python3 tests/https_apache_test.py
```

Der Integrationstest verwendet ein temporäres Verzeichnis, eigene Test-CA und
harmlose PHP-Dummies für die Endpunkte. Auf macOS nutzt er PHP-FastCGI; die
Produktivinstallation auf Raspberry Pi OS verwendet weiterhin das vorhandene
Apache-PHP-Modul. Die Debian-systemd-/nftables-Aktivierung ist zusätzlich am
Test-Pi zu prüfen.

Abnahme am Pi und an beiden iPads:

1. HTTP-Anleitung, dauerhaften CA-Download und Wartezimmer-Betrieb prüfen.
2. CA einmal installieren und volles Vertrauen aktivieren; HTTPS ohne Warnung.
3. HTTPS `/`, Auswahl, direkte Tablet-Adressen, Formulare und Assets prüfen.
4. Seriennummer/Fingerabdruck des Serverzertifikats sowie CA-Fingerabdruck notieren.
5. Erneuerung erzwingen; Serverzertifikat muss wechseln, CA muss gleich bleiben.
6. Auf beiden iPads erneut ohne Zertifikatsinstallation zugreifen.
7. Timer und Journal prüfen; private Dateien dürfen weder über Samba/HTTP/HTTPS
   noch durch den PHP-Benutzer lesbar sein.

Ein mutmaßlich „öffentlicher“ Wartezimmer-Aufruf darf für eine technische Probe
nicht ungeplant ausgeführt werden, weil er eine GDT-Datei konsumiert. Die
Betriebsprüfung erfolgt mit einem bewusst angelegten Testaufruf.
