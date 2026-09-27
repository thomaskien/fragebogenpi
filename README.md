# fragebogenpi

www.fragebogenpi.de

**fragebogenpi** ist ein Installations- und System-Setup für einen Raspberry Pi, der als isolierter Fragebogen- und Datenerfassungs-Server betrieben wird.

Ziel ist:
- Daten strukturiert in das Praxisverwaltungssystem zu bekommen
- Entwickelt für T2med -> modifizierbar für andere systeme
- **Anamnesebögen für Neupatienten**
- Patientenfoto für die Kartei
- optional: **Patientenaufruf auf einem Bildschirm**
- Befundfotos direkt in die Kartei vom Handy


[![Video-Titel](https://img.youtube.com/vi/nMGKcn7A4_Y/hqdefault.jpg)](https://www.youtube.com/watch?v=nMGKcn7A4_Y)




iPad:

<img src="https://github.com/thomaskien/fragebogenpi/blob/main/IMG_1169.png" alt="drawing" width="800"/>

Wird zu:

<img src="https://github.com/thomaskien/fragebogenpi/blob/main/Screenshot 2026-02-01 at 00.28.35.png" alt="drawing" width="800"/>



Man braucht:
- **kein teures medizinsoftwarebla für xxxx,xx Euro**
- einen Raspberry ab version 4
- installieren mit Raspberry OS (ich nehme light) z.B. version 13
- eine High-Endurance-SD
- ein Plastikgehäuse für den Raspberry damit das WLAN nicht abgeschirmt wird
- Einen Netzwerkanschluss in der Nähe des Wartezimmers
- ein (altes) iPad für die Anamnesebögen
- ein (altes) iPhone für Kartei-Selfie wenn man möchte
- Befunde kann man mit seinem normalen Handy Fotografieren wenn es per VPN oder WLAN im Praxisnetz ist

Das Projekt richtet einen Raspberry Pi so ein, dass:
- im **LAN** ein normal erreichbarer Web- und Samba-Server läuft
- im **WLAN** ein **isoliertes Netz** („fragebogenpi“) bereitgestellt wird, das **ausschließlich** Zugriff auf den lokalen Webserver erlaubt
- **kein Routing** ins LAN oder Internet möglich ist

---

## Kernfunktionen

- **WLAN-Access-Point**
  - SSID: `fragebogenpi`
  - eigenes Subnetz (kein Internet, kein LAN-Zugriff)
  - nur HTTP/HTTPS erlaubt
  - SSH & SMB im WLAN blockiert

- **LAN-Anbindung**
  - Webserver (HTTP / optional HTTPS)
  - Samba-Shares
  - SSH uneingeschränkt im LAN verfügbar

- **Webserver**
  - Apache + PHP
  - optional HTTPS (self-signed Zertifikat, gültig bis 2050)
  - PHP-Schreibzugriff auf definierte Datenverzeichnisse

- **Datenablage (Variante A)**
  - `/srv/fragebogenpi/GDT`
  - `/srv/fragebogenpi/PDF`
  - **nicht** direkt per Web erreichbar
  - PHP (`www-data`) kann schreiben
  - Zugriff per Samba im LAN

- **Samba**
  - `GDT`, `PDF` (optional anonym oder per User `fragebogenpi`)
  - `WEBROOT` (`/var/www/html`) nur für Admin-User
  - Samba ausschließlich im LAN verfügbar

- **Sicherheit**
  - nftables-Firewall
  - WLAN strikt eingeschränkt
  - kein IP-Forwarding / kein Routing
  - SSH nur per Firewall im WLAN blockiert (sshd läuft normal)

---

## Installation

einloggen in den raspberry pi über SSH oder mit tastatur und maus eine kommandozeile öffnen

```bash
wget https://raw.githubusercontent.com/thomaskien/fragebogenpi/refs/heads/main/fragebogenpi.sh
chmod +x fragebogenpi.sh
sudo bash ./fragebogenpi.sh
```

Für den **Wartezimmer-Aufrufschirm** auf ZWEITEM Raspberry pi:

```bash
wget https://raw.githubusercontent.com/thomaskien/fragebogenpi/refs/heads/main/wartezimmer.sh
chmod +x wartezimmer.sh
sudo bash ./wartezimmer.sh
```

## Mehrgeraetebetrieb der Tablet-Formulare

Der Installer fragt, ob ein oder mehrere Tablets verwendet werden. Die
PHP-Dateien muessen bei mehreren Tablets nicht manuell dupliziert werden.
Der Installer legt automatisch `tablet1.php`, `tablet2.php` usw. an, maximal
bis `tablet9.php`.

Bei nur einem Tablet wird verwendet:

```text
Web-App:    tablet.php
Eingabe:    anam-i.gdt
Antwort:    anam-o.gdt
```

Bei mehreren Tablets erhaelt jedes Geraet eine eigene Web-App und ein eigenes
GDT-Praefix:

```text
Tablet 1:   tablet1.php     1-anam-i.gdt     1-anam-o.gdt
Tablet 2:   tablet2.php     2-anam-i.gdt     2-anam-o.gdt
```

Tablet 1 verarbeitet ausschliesslich GDT-Dateien mit `1-`, Tablet 2
ausschliesslich Dateien mit `2-` usw. Alle Tablets verwenden weiterhin den
gleichen flachen GDT-Ordner. Es gibt keine getrennten Warteschlangen oder
Unterverzeichnisse.

Im Mehrgeraetebetrieb ist `tablet.php` selbst nicht aktiv; verwendet werden
die erzeugten Endpunkte `tablet1.php` bis `tabletN.php`. Die Anzahl der
Tablets wird vom Installer gespeichert und kann bei einer erneuten
Einrichtung angepasst werden.

## Formularfolgen mit gemeinsamer GDT-Antwort

Seit `tablet.php` **1.8.3** werden die Ergebnisse eines Startbogens und seiner
bedingten Folgeformulare gemeinsam zurueckgegeben. Beispiel:

```text
ana-i.gdt -> Anamnese -> ISI -> PHQ-9 -> ana-o.gdt
```

Die Antwortdatei entsteht erst nach Abschluss der gesamten Folge. Sie enthaelt
die Ergebnisse aller beantworteten Boegen. Folgeformulare werden intern
verwaltet; fuer sie entstehen keine eigenen `-i.gdt` oder `-o.gdt`.
Die Namen und Tablet-Praefixe des Startauftrags bleiben erhalten, beispielsweise
`1-anam-i.gdt` -> `1-anam-o.gdt`.

Einzelaufrufe bleiben moeglich: Ein separat angefordertes `isi-i.gdt` erzeugt
weiterhin `isi-o.gdt`. In der Praxissoftware wird eine eigene GDT-Einrichtung
daher nur fuer die Boegen benoetigt, die direkt gestartet werden sollen.
Mehrere eigenstaendige Auftraege bleiben auch beim selben Patienten getrennt.

`follow_up_forms` in den YAML-Dateien funktioniert unveraendert. Alle Ziel-YAMLs
muessen im Formular-Share liegen; numerische Dateipraefixe bestimmen die
Reihenfolge innerhalb der Folge. Wiederholte Ziele werden pro Formular-ID nur
einmal bearbeitet. Formulare mit eigenem `meta.handler`, etwa die
Datenschutz-Unterschrift, werden weiterhin separat angefordert.

Die Antworten werden nach jedem abgesendeten Bogen im GDT-Verzeichnis in
verborgenen `.fragebogenpi-chain-*.json`-Dateien zwischengespeichert. Diese
enthalten Patientendaten und gehoeren nicht ins Webroot oder Git-Repository.
Beim Abschluss werden sie zusammen mit dem Startauftrag entfernt. Wird der
Startauftrag manuell entfernt, werden seine Zwischenstaende beim naechsten
Aufruf dieses Tablets verworfen. Auftraege waehrend einer laufenden Folge nicht
ersetzen; ein erkannter Wechsel wird ohne Vermischung der Antworten blockiert.

Beim Abbruch eines Folgeformulars bleiben die vorherigen Antworten erhalten;
der ausgelassene Bogen wird in der gemeinsamen Antwort gekennzeichnet und
weitere offene Boegen werden angeboten. Ein Abbruch des noch unbeantworteten
Startbogens verwirft den Auftrag ohne Antwortdatei.

Bereits vorhandene Antwortdateien werden nicht ueberschrieben. Nach ihrem
Import kann die gespeicherte Antwort durch erneutes Absenden oder Neuladen
bereitgestellt werden. Bei einem Prozessabbruch genau waehrend der Publikation
kann der Importstatus unklar sein: Dann bleiben die Daten gespeichert und die
Praxis muss pruefen, ob der Import bereits erfolgt ist, bevor sie den Auftrag
bereinigt. Eine moeglicherweise schon importierte Antwort wird nicht automatisch
ein zweites Mal erzeugt.

Zum Aktualisieren `tablet.php` (bei mehreren Tablets entsprechend auch
`tablet1.php` bis `tabletN.php`) im WLAN-Webroot ersetzen und die benoetigten
YAML-Dateien aus `_yaml/` in den Formular-Share uebernehmen. Bereits nach dem
alten Verfahren erzeugte Folge-GDTs bleiben eigenstaendige Auftraege; das Update
daher zwischen abgeschlossenen Formularfolgen durchfuehren.

Regressionstest ohne Zugriff auf reale Patientendaten:

```bash
php -l tablet.php
php tests/tablet_form_chains_test.php
```




<img src="https://github.com/thomaskien/fragebogenpi/blob/main/Screenshot%202026-01-31%20at%2021.04.02.png" alt="drawing" width="700"/>

Im T2med muss man geräte anlegen, die beispieldateien sind runterzuladen z.B. GDTGeraet_Selfie_Konfiguration.json


<img src="https://github.com/thomaskien/fragebogenpi/blob/main/Screenshot 2026-01-31 at 21.29.37.png" alt="drawing" width="800"/>

Das "Programm" ist hier irrelevant, kann aber nicht frei bleiben.

# Bilderstrecke

Standby am Mobilgerät für Selfie:

<img src="https://github.com/thomaskien/fragebogenpi/blob/main/9A8AEC1B-1EE7-4F10-817A-ED19C3FB55D8.png" alt="drawing" width="300"/>

Übertragen der Patientendaten für die Zuordnung:

<img src="https://github.com/thomaskien/fragebogenpi/blob/main/Screenshot%202026-01-31%20at%2020.42.41.png" alt="drawing" width="800"/>

Selfie:

<img src="https://github.com/thomaskien/fragebogenpi/blob/main/8ECF114B-8403-4448-AA1B-5C730D52FE16.png" alt="drawing" width="300"/>

oder Befund

<img src="https://github.com/thomaskien/fragebogenpi/blob/main/D0ACECB9-47EB-4619-84EF-C2F40E4E724F.png" alt="drawing" width="300"/>

Eingang des Selfies:

<img src="https://github.com/thomaskien/fragebogenpi/blob/main/Screenshot%202026-01-31%20at%2020.43.44.png" alt="drawing" width="800"/>

Eingang des Befunds:

<img src="https://github.com/thomaskien/fragebogenpi/blob/main/Screenshot%202026-01-31%20at%2020.45.40.png" alt="drawing" width="800"/>

Ansicht in der Akte:

<img src="https://github.com/thomaskien/fragebogenpi/blob/main/Screenshot%202026-01-31%20at%2020.46.29.png" alt="drawing" width="800"/>


# PVS
- T2med siehe screenshots
- x.concept läuft mit $ENABLE_XCONCEPT_3000_END_WORKAROUND = true; und aktuell noch einer weiteren anpassung im code (anleitung folgt)
- tomedo läuft, man muss "bei der Kodierung  NSUTF8StringEncoding wählen"



# FUNKTIONEN:


# Selfie-Erfassung (fragebogenpi)
(analog Befunderfassung)

Diese Funktion ermöglicht es, **Patientenfotos (Selfies)** direkt über ein mobiles Endgerät aufzunehmen  
und **kontrolliert per GDT** an die Praxissoftware zu übergeben.

Der Workflow ist bewusst **einfach, fehlertolerant und eindeutig**, um Verwechslungen zu vermeiden.

---

## Überblick

- 📄 Auftragssteuerung **ausschließlich über GDT**
- 📱 Aufnahme über **mobilen Browser (iOS/Android)**
- 🖼️ Bild wird **clientseitig skaliert (max. 800 px)** (nur selfie)
- 📎 Übergabe als **JPEG-Anhang per Antwort-GDT (6310)**
- 🧹 Automatisches Aufräumen (Auftragsdatei wird gelöscht)

---

## Technische Eckdaten

| Punkt | Wert |
|-----|-----|
| PHP-Datei | `selfie.php` |
| Auftragsdatei | `SLFT2MD.gdt` |
| Antwortdatei | `T2MDSLF.gdt` |
| Bildname | `selfie.jpg` |
| Verzeichnis | `/srv/fragebogenpi/GDT` |
| Max. Bildkante | 800 px |
| Version | ≥ v2.0 |

---

## Ablauf (Workflow)

### 1️⃣ Auftrag aus der Praxissoftware

Die Praxissoftware legt im GDT-Verzeichnis eine **Auftragsdatei** an:

/srv/fragebogenpi/GDT/SLFT2MD.gdt


Diese Datei enthält u. a.:

- Patienten-ID (3000)
- Vorname / Nachname (3102 / 3101)
- Kommunikationsfelder (8315 / 8316)

👉 **Nur wenn diese Datei existiert**, wird die Aufnahmeoberfläche freigeschaltet.

---

### 2️⃣ Warten auf Auftrag (Browser)

Solange **keine** `SLFT2MD.gdt` vorhanden ist:

- wird der Patient **namentlich angezeigt**
- aktualisiert sich die Seite **automatisch alle 3 Sekunden**
