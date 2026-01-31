# fragebogenpi

**fragebogenpi** ist ein Installations- und System-Setup für einen Raspberry Pi, der als isolierter Fragebogen- und Datenerfassungs-Server betrieben wird.

Ziel ist:
- Daten strukturiert in das Praxisverwaltungssystem zu bekommen
- Entwickelt für T2med -> modifizierbar für andere systeme
- **Anamnesebögen für Neupatienten**
- **Patientenfoto für die Kartei**
- **Befundfotos direkt in die Kartei vom Handy**

Man braucht:
- **kein teures medizinsoftwarebla für xxxx,xx Euro**
- einen Raspberry ab version 4
- installieren mit Raspberry OS (ich nehme light)
- eine High-Endurance-SD
- ein Plastikgerhäuse für den Raspberry damit das WLAN noch funktioniert
- Einen Netzwerkanschluss in der Nähe des Wartezimmers
- ein altes iPad für die Anamnesebögen
- ein altes iPhone für Kartei-Selfie wenn man möchte
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

📸 **Screenshot (Software 1):**


Screenshot 2026-01-31 at 20.24.41.png

3️⃣ Aufnahme auf dem Mobilgerät

Sobald die Auftragsdatei vorhanden ist:

    Anzeige Vorname Nachname (sehr groß)

    Buttons:

        Selfie neu aufnehmen

        Speichern (anfangs deaktiviert)

        Abbruch

📱 Screenshots (Mobilgerät):

Screenshot_Mobile_01_Start.png
Screenshot_Mobile_02_Kamera.png
Screenshot_Mobile_03_Vorschau.png

Wichtig:

    „Speichern“ wird erst aktiv, wenn die Vorschau erfolgreich geladen wurde

    verhindert versehentliches Absenden ohne Bild

4️⃣ Speichern & Übertragung

Beim Klick auf „Speichern“:

    Bild wird clientseitig skaliert (Canvas → JPEG)

    selfie.jpg wird im GDT-Verzeichnis abgelegt

    T2MDSLF.gdt wird erzeugt (Satzart 6310)

    SLFT2MD.gdt wird automatisch gelöscht

    Browser lädt neu

📸 Screenshots (Software):

Screenshot 2026-01-31 at 20.43.44.png
Screenshot 2026-01-31 at 20.45.40.png
Screenshot 2026-01-31 at 20.46.29.png

5️⃣ Abbruch (optional)

Der Button „Abbruch“:

    löscht nur die SLFT2MD.gdt

    erzeugt keine Antwort-GDT

    kehrt in den Wartezustand zurück

Geeignet bei:

    falschem Patienten

    Aufnahme verweigert

    Bedienfehler

Antwort-GDT (Auszug)

Die erzeugte Antwortdatei T2MDSLF.gdt enthält u. a.:

    Satzart 6310

    Patienten-ID (3000)

    Anhang:

        6302 Anzahl: 000001

        6303 Typ: JPG

        6304 Beschreibung: Selfie

        6305 Dateiname: selfie.jpg

Sicherheit & Robustheit

    ✔ keine Bildverarbeitung serverseitig (kein GD nötig)

    ✔ klare Dateinamen (keine Zufallsnamen)

    ✔ deterministischer Workflow (1 Auftrag → 1 Antwort)

    ✔ keine Vermischung mit anderen GDT-Prozessen

Versionierung

Aktuelle Version: v2.0

Footer im UI:

fragebogenpi (selfie.php) von Dr. Thomas Kienzle 2026

Nächste mögliche Erweiterungen (optional)

    ⏱️ Timeout-Löschung bei Inaktivität

    🔒 Dateisperre (flock) bei parallelem Zugriff

    🧾 Logdatei je Auftrag

    🖼️ Mehrere Bilder pro Auftrag
