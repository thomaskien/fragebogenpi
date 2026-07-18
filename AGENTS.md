# AGENTS.md - Pflegehinweise fuer Codex

Diese Datei haelt den aktuell bestaetigten Projektstand, zwingende Arbeitsregeln und offene Installer-Wuensche fuer `fragebogenpi` fest. Sie ist fuer kuenftige Codex-/Agenten-Laeufe verbindlicher Kontext.

## Zusaetzlicher verbindlicher Kontext

Fuer Arbeiten an `anamnesebogen.yaml` gelten die gesonderten Regeln und der
aktuelle bestaetigte Stand in `ANAMNESEBOGEN.md`. Diese Datei vor jeder
Aenderung am Anamnesebogen lesen.

## Projektziel

`fragebogenpi.sh` ist ein interaktiver Installer fuer Raspberry Pi OS. Er richtet einen Raspberry Pi fuer Fragebogen-/Praxis-Anwendungen ein:

- Apache + PHP
- Samba-Sharing fuer GDT, PDF und Webroot
- isolierten WLAN-Access-Point `fragebogenpi`
- hostapd + dnsmasq
- Firewall-Regeln mit WLAN-Isolation
- optional HTTPS mit selbstsigniertem Zertifikat
- Bootstrap-Download der Webanwendung aus GitHub
- automatische Sicherheitsupdates
- Benutzerverwaltung fuer Samba/Windows-Clients
- Admin-User mit SSH- und sudo-Zugang

Die derzeit bestaetigten Basisversionen sind:

```text
fragebogenpi.sh v1.7.0
wartezimmer.sh v1.5.6
```

Diese Datei ist die verbindliche Ausgangsbasis. Nicht neu rekonstruieren und nicht auf aeltere Varianten zurueckfallen.

## Zwingende Arbeitsregeln

1. Immer auf der vom Nutzer bestaetigten Ausgangsdatei aufbauen.
2. Aenderungen konservativ halten:
   - so wenige Aenderungen wie moeglich
   - keine unaufgeforderten Refactorings
   - keine Umbenennungen oder Strukturaenderungen ohne klaren Grund
3. Versionierung:
   - notwendige Aenderungen standardmaessig in Schritten von `0.0.1`
   - eine andere Versionsstufe nur verwenden, wenn der Nutzer sie ausdruecklich vorgibt
4. Changelog:
   - immer vollstaendig fortfuehren
   - nie alte Changelog-Eintraege entfernen
   - neuen Eintrag oben an die bisherigen Versionen anhaengen
5. Vor Ausgabe einer kompletten Datei:
   - erst die geplanten Aenderungen kurz analysieren und bestaetigen lassen
   - danach erst die vollstaendige Datei ausgeben
6. Bei Unsicherheit ueber die passende Ausgangsdatei:
   - nicht improvisieren
   - nach der bestaetigten Datei fragen
7. Vor Ausgabe von Bash-Dateien mindestens gedanklich pruefen:
   - `set -euo pipefail`
   - Variablen-Scope in Funktionen
   - Command Substitution `$(...)`
   - stdout/stderr-Trennung
   - heredocs und Quotes
   - systemd-/nftables-Syntax
   - Reihenfolge von Dienststarts

## Installer-Aenderungen seit v1.5.8

Diese Punkte sind in `fragebogenpi.sh` seit v1.5.8 umgesetzt:

- Der Installer soll fragen, ob der Hostname neu gesetzt werden soll.
  - Wenn ja, nach Hostname fragen.
  - Standardwert/Vorschlag: `fragebogenpi`.
  - Wenn nein, bestehenden Hostname unveraendert lassen.
  - Hostname-Aenderung betrifft `hostnamectl` bzw. `/etc/hostname` sowie die Raspberry-Pi-typische `127.0.1.1`-Zeile in `/etc/hosts`; bei "nein" bleibt beides unangetastet.
- Der Installer soll beim WLAN-Namen/SSID ebenfalls fragen, ob dieser gesetzt/geaendert werden soll.
  - Wenn ja, nach SSID fragen.
  - Wenn nein, bestehende SSID unveraendert lassen.
  - Diese Vorabfrage gilt nicht fuer das WLAN-Passwort.
- Eine bestehende Samba-Konfiguration darf nicht entfernt oder ueberschrieben werden.
  - Beispiel: Wenn bereits `kienzlefax` installiert/eingerichtet ist, darf dessen Samba-Setup nicht geloescht oder beschaedigt werden.
  - Der Installer soll nur die fuer `fragebogenpi` noetigen Samba-Anteile hinzufuegen oder aktualisieren.
  - Bestehende Shares, globale Samba-Einstellungen und Includes moeglichst unangetastet lassen.

## Installer-Aenderungen seit v1.5.9

Diese Punkte sind in `fragebogenpi.sh` seit v1.5.9 umgesetzt:

- WLAN und LAN haben getrennte Webroots:
  - WLAN/fragebogenpi-App: `/srv/fragebogenpi/webroot-wlan`
  - bestehender LAN-Webroot: `/var/www/html`
- Samba-Shares fuer Webroots sind getrennt:
  - `webroot-wlan` -> `/srv/fragebogenpi/webroot-wlan`
  - `webroot-lan` -> `/var/www/html`
  - alte `WEBROOT`-Abschnitte werden durch die beiden neuen Shares ersetzt
  - fremde Shares wie `kienzlefax` oder `telepraxis` muessen erhalten bleiben
- Apache ist getrennt:
  - Standard-`apache2` wird per Helper/Drop-in auf die aktuelle LAN-IP gebunden
  - `fragebogenpi-apache-wlan.service` bedient nur `${AP_IP}` bzw. `10.23.0.1`
  - die WLAN-Instanz nutzt ausschliesslich den WLAN-Webroot
  - WLAN darf keine anderen Apache-Anwendungen wie `kienzlefax` oder `telepraxis` erreichen
- Firewall:
  - aus dem WLAN werden nur HTTP und bei aktivem HTTPS zusaetzlich HTTPS zur AP-IP erlaubt
  - im HTTP-only-Modus darf TCP/443 aus dem WLAN nicht pauschal offen sein

## Installer-Aenderungen seit v1.6.3

- Neuer additiver Tablet-/Formularmodus:
  - bei bestehender Installation als eigener Modus auswaehlbar
  - bestehende WLAN-, LAN-, Hostname-, Firewall- und Samba-Konfiguration bleibt unangetastet
  - neuer Share `formulare` -> `/srv/fragebogenpi/formulare`
  - `anamnesebogen.yaml` wird als `anam.yaml` in den neuen Formular-Share kopiert
  - bei einem Tablet wird `tablet.php` bereitgestellt
  - bei mehreren Tablets werden `tablet1.php` bis `tabletN.php` bereitgestellt
  - GDT-Eingaben verwenden `anam-i.gdt` beziehungsweise `1-anam-i.gdt`

## Aktueller Funktionsumfang

### Folgeformulare im Tablet-Betrieb

`tablet.php` unterstuetzt in den YAML-Dateien optional:

```yaml
follow_up_forms:
  - form: act
    when:
      id: asthma
      equals: true
```

Nach dem Absenden wird die Ziel-GDT als `act-i.gdt` beziehungsweise mit
Tablet-Praefix angelegt. Das Ziel-YAML muss im Formular-Share vorhanden sein;
seine optionale Prioritaet wird weiterhin ueber den YAML-Dateinamen bestimmt,
zum Beispiel `5-act.yaml`. Folgeformulare duerfen ihrerseits weitere
Folgeformulare ausloesen.

### Netzwerk und WLAN

- WLAN-Access-Point:
  - Interface: `wlan0`
  - SSID: `fragebogenpi`
  - IP: `10.23.0.1/24`
  - DHCP-Bereich: `10.23.0.50` bis `10.23.0.150`
  - kein Routing vom WLAN ins LAN oder Internet
  - WLAN-Clients duerfen nur HTTP/HTTPS zum Pi nutzen
  - SSH und SMB sind auf WLAN blockiert
- LAN:
  - Interface: `eth0`
  - LAN soll vollstaendig unberuehrt und internetfaehig bleiben
  - Samba ist nur ueber `eth0` gebunden
  - SSH ist ueber LAN moeglich
- hostapd:
  - `country_code=DE`
  - `ieee80211d=1`
  - `ieee80211n=1`
  - Kanal 6, 2,4 GHz
  - WPA2-PSK mit generiertem Passwort
- NetworkManager:
  - wenn aktiv, wird `wlan0` als unmanaged gesetzt
  - damit NetworkManager den Access-Point nicht stoert
- AP-IP:
  - falls kein `dhcpcd` vorhanden ist, wird ein eigener systemd-Oneshot-Service verwendet:
    - `/etc/systemd/system/fragebogenpi-ap-ip.service`
    - `/usr/local/sbin/fragebogenpi-ap-ip.sh`

### Firewall

Aktuelle relevante Regelstrategie:

- eigene nftables-Tabelle `inet fragebogenpi`
- kein globales `flush ruleset`
- dadurch sollen fremde oder bestehende Netzwerkregeln nicht zerstoert werden
- `eth0` bleibt unberuehrt
- Forwarding wird nur zwischen/ueber `wlan0` blockiert
- `net.ipv4.ip_forward=0`
- `net.ipv6.conf.all.forwarding=0`

Wichtig: Fruehere Varianten mit `flush ruleset` fuehrten vermutlich zu fehlender Internet-Konnektivitaet auf dem Pi. Das darf nicht wieder eingefuehrt werden.

### Samba

Shares:

```text
GDT           -> /srv/fragebogenpi/GDT
PDF           -> /srv/fragebogenpi/PDF
webroot-wlan  -> /srv/fragebogenpi/webroot-wlan
webroot-lan   -> /var/www/html
```

- GDT/PDF optional anonym oder passwortgeschuetzt
- webroot-wlan/webroot-lan nur fuer den Admin-User
- Samba bindet nur an `lo` und `eth0`
- SMB2/SMB3
- Bestehende fremde Samba-Konfigurationen muessen erhalten bleiben.

### Admin-User

Der User `admin` wird als Linux- und Samba-User angelegt.

Sollzustand:

```text
Linux-Shell: /bin/bash
Linux-Passwort: gesetzt
Gruppenzugehoerigkeit: sudo
Samba-Passwort: gesetzt
SSH ueber LAN: moeglich
webroot-wlan/webroot-lan-Samba-Shares: moeglich
```

Beim weiteren Umbau darauf achten, dass `admin` niemals versehentlich mit `/usr/sbin/nologin` angelegt oder ueberschrieben wird.

### Zusaetzliche Windows-/Samba-User

Seit v1.5.6 werden zusaetzliche User einzeln und interaktiv bearbeitet:

1. Username eingeben
2. Passwort manuell eingeben oder generieren
3. Linux-User sicherstellen
4. Samba-User anlegen oder aktualisieren
5. Samba-User aktivieren
6. Login-Test durchfuehren

Der Dialog endet mit leerem Usernamen.

Bestehende User sollen ueber denselben Weg reparierbar sein:

- gleichen Usernamen erneut eingeben
- neues Passwort waehlen
- Samba-Passwort wird aktualisiert
- Samba-User wird aktiviert

## Kritische Erkenntnis: Passwortabfrage und stdout/stderr

Dies war ein realer Fehler und ist dauerhaft zu beachten.

Problem:

```bash
pw="$(ask_password_twice ...)"
```

Wenn `ask_password_twice()` Prompts, Zeilenumbrueche oder Fehlermeldungen auf stdout schreibt, werden diese mit in `pw` uebernommen. Das fuehrte zu falschen Samba-Passwoertern bzw. Fehlern wie:

```text
Mismatch - password unchanged.
Unable to get new password.
```

Die korrekte Regel lautet:

- Prompts, sichtbare Zeilenumbrueche und Fehlermeldungen: ausschliesslich `stderr`
- Nur das tatsaechliche Passwort: `stdout`
- Keine zusaetzlichen Newlines auf stdout

Aktuelle Sollfunktion:

```bash
ask_password_twice() {
  local prompt="$1"
  local p1="" p2=""

  while true; do
    read -r -s -p "${prompt}: " p1 >&2
    printf '\n' >&2
    read -r -s -p "${prompt} (Wiederholung): " p2 >&2
    printf '\n' >&2

    p1="${p1%$'\r'}"
    p2="${p2%$'\r'}"

    [[ -n "$p1" ]] || {
      echo "Passwort darf nicht leer sein." >&2
      continue
    }

    if [[ "$p1" == "$p2" ]]; then
      printf '%s' "$p1"
      return 0
    fi

    echo "Passwoerter stimmen nicht ueberein. Bitte erneut." >&2
  done
}
```

Diese Trennung ist zwingend beizubehalten.

## Samba-Passwortsetzung und Pruefung

Samba-User muessen je nach Existenz unterschiedlich behandelt werden:

```bash
samba_user_exists() {
  local u="$1"
  pdbedit -L 2>/dev/null | awk -F: '{print $1}' | grep -qx "$u"
}
```

```bash
set_samba_password_add_or_update() {
  local u="$1"
  local pw="$2"

  if samba_user_exists "$u"; then
    printf '%s\n' "$pw" "$pw" | smbpasswd -s "$u"
  else
    printf '%s\n' "$pw" "$pw" | smbpasswd -a -s "$u"
  fi

  smbpasswd -e "$u" >/dev/null 2>&1 || true
}
```

Wichtig:

- existierender Samba-User: `smbpasswd -s`
- neuer Samba-User: `smbpasswd -a -s`
- keine unzuverlaessigen `echo`-Pipelines verwenden
- immer `printf '%s\n' "$pw" "$pw"`

Nach jeder Passwortsetzung erfolgt ein Login-Test:

```bash
smbclient -L 127.0.0.1 -U "${u}%${pw}" -m SMB3
```

Dieser Test muss bei Fehler das Script klar abbrechen oder zumindest deutlich melden. Der Nutzer hat ausdruecklich bestaetigt, dass die korrigierte stdout/stderr-Trennung das Passwortproblem behoben hat.

Benoetigte Pakete:

```text
samba
samba-common-bin
smbclient
```

## Bootstrap-Update

Bootstrap-Quelle:

```text
https://raw.githubusercontent.com/thomaskien/fragebogenpi/refs/heads/main/bootstrap
```

Die Bootstrap-Datei enthaelt relative Dateipfade.

Regeln:

- Kommentare und leere Zeilen ignorieren
- CRLF am Zeilenende entfernen
- keine absoluten Pfade
- keine `..`-Pfadsegmente
- Dateien relativ zum Bootstrap-Verzeichnis herunterladen
- Ziel: `/srv/fragebogenpi/webroot-wlan`

Wichtiger Scope-Fix:

```bash
local tmp_list
tmp_list="$(mktemp)"
trap 'rm -f "$tmp_list"' RETURN
```

Nicht `EXIT` verwenden, weil `tmp_list` lokal ist und mit `set -u` beim Script-Ende zu folgendem Fehler fuehrte:

```text
tmp_list: unbound variable
```

## Installationsmodi bei bestehendem System

Wenn `/srv/fragebogenpi` existiert, zeigt der Installer:

```text
1) Vollstaendige Neu-Konfiguration
2) Nur Webroot-Update
3) Nur User hinzufuegen / reparieren
```

### Modus 1

Vollinstallation bzw. Neu-Konfiguration:

- setzt Konfiguration neu
- generiert neue Standardpasswoerter
- richtet Dienste, Samba, WLAN, Firewall und PHP ein
- startet am Ende Reboot

### Modus 2

Nur Bootstrap-/Webroot-Update:

- nur Dateien aus Bootstrap aktualisieren
- keine Passwortaenderungen
- keine Netzwerk-/Firewall-/Samba-Aenderungen

### Modus 3

Nur User hinzufuegen oder reparieren:

- nur Samba-/Linux-User bearbeiten
- keine Aenderungen an WLAN, Firewall, Webroot, Apache oder Shares
- User einzeln abfragen
- Passwort setzen und Login-Test durchfuehren

## Benutzerloeschung und Reboot

Am Ende der Vollinstallation:

- optionaler Loeschdialog fuer einen bestehenden Systemuser
- Standardvorschlag: `pi`
- aktueller Benutzer darf grundsaetzlich ausgewaehlt werden
- wenn der User gerade in Benutzung ist, kann `userdel -r` scheitern
- dann wird ein Oneshot-Service fuer Loeschung beim naechsten Boot eingerichtet

Dateien dafuer:

```text
/etc/fragebogenpi/delete_user
/usr/local/sbin/fragebogenpi-delete-user.sh
/etc/systemd/system/fragebogenpi-delete-user.service
```

Reboot:

- nicht `shutdown -r +0.166` verwenden
- dieses Zeitformat ist ungueltig
- aktueller Ansatz:

```bash
nohup bash -c 'sleep 10; systemctl reboot >/dev/null 2>&1 || /sbin/reboot >/dev/null 2>&1 || reboot >/dev/null 2>&1' >/dev/null 2>&1 &
```

## Bekannte fruehere Fehler und Loesungen

### `Mismatch - password unchanged`

Ursache:

- Passwort enthielt zusaetzliche Newlines aus Command Substitution
- oder fehlerhafte Passwortuebergabe an `smbpasswd`

Loesung:

- `ask_password_twice()` stdout sauber halten
- `printf '%s\n' "$pw" "$pw" | smbpasswd ...`
- `smbclient`-Login-Test

### Bootstrap bricht mit NUL-Fehler ab

Ursache:

- Bash kann kein echtes NUL in Variablen speichern
- ein Test mit `$'\0'` matchte dadurch faelschlich immer

Loesung:

- NUL-Check entfernt
- CRLF am Zeilenende entfernen

### `tmp_list: unbound variable`

Ursache:

- EXIT-Trap griff nach Ende des lokalen Funktionsscopes auf `tmp_list` zu

Loesung:

- `trap ... RETURN`

### Reboot funktionierte nicht

Ursache:

```bash
shutdown -r +0.166
```

ist ungueltig.

Loesung:

- zeitverzoegerter, losgeloester `nohup bash -c 'sleep 10; systemctl reboot ...'`

### Internet/LAN-Konnektivitaet verschwand

Verdacht/Ursache:

- `flush ruleset` in `/etc/nftables.conf`

Loesung:

- keine globale nftables-Leerung
- eigene Tabelle `inet fragebogenpi`
- nur WLAN-bezogene Regeln

### WLAN sichtbar, aber Clients konnten nicht verbinden

Verbesserungen seit 1.5.5:

```text
country_code=DE
ieee80211d=1
ieee80211n=1
```

sowie stabilere Startreihenfolge:

1. AP-IP setzen
2. hostapd starten
3. dnsmasq starten

## Empfohlene Tests nach jeder Aenderung

Syntax:

```bash
bash -n fragebogenpi.sh
```

Vor Ausfuehrung auf Testsystem:

```bash
sudo bash -x ./fragebogenpi.sh
```

Nach Vollinstallation:

```bash
systemctl status hostapd --no-pager
systemctl status dnsmasq --no-pager
systemctl status smbd --no-pager
systemctl status nftables --no-pager
```

Netzwerk:

```bash
ip -4 addr show eth0
ip -4 addr show wlan0
ip route
ping -c 2 1.1.1.1
```

WLAN-Konfiguration:

```bash
grep -E '^(ssid|wpa_passphrase|country_code|channel)=' /etc/hostapd/hostapd.conf
```

Admin pruefen:

```bash
getent passwd admin
passwd -S admin
id admin
sshd -T | grep -i passwordauthentication
```
