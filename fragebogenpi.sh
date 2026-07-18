#!/usr/bin/env bash
#
# fragebogenpi.sh
# Projekt: fragebogenpi
# Autor: Thomas Kienzle
#
# Version: 1.6.4
#
# =========================
# Changelog (vollständig)
# =========================
#
# - 1.6.4 (2026-07-18)
#   * Neuer Tablet-/Formularbetrieb ergänzt:
#       - Installer fragt nach einem oder mehreren Tablets
#       - tablet.php beziehungsweise tablet1.php bis tablet9.php werden bereitgestellt
#       - Formular-Share /srv/fragebogenpi/formulare wird ergänzt
#       - anamnesebogen.yaml wird als anam.yaml in den Formular-Share kopiert
#   * Bei bestehender Installation steht dafür ein additiver Einrichtungsmodus zur Verfügung.
#       - bestehende WLAN-, LAN-, Hostname-, Firewall- und Samba-Konfiguration bleibt unangetastet
#
# - 1.6.3 (2026-07-18)
#   * Bugfix der temporären Dateibereinigung:
#       - alle verbliebenen RETURN-Traps werden nach ihrer ersten Ausführung entfernt
#       - verhindert weitere "unbound variable"-Fehler beim Verlassen übergeordneter Funktionen
#
# - 1.6.2 (2026-07-18)
#   * Bugfix beim Download von wartezimmer-server.php:
#       - temporärer RETURN-Trap wird nach der Bereinigung entfernt
#       - verhindert "tmp: unbound variable" beim Abschluss der Wartezimmer-Einrichtung
#
# - 1.6.1 (2026-07-18)
#   * Bugfix der Apache-Dienststeuerung bei der Wartezimmer-Einrichtung:
#       - LAN-Bind-Hilfsdienst bleibt nach erfolgreicher Ausführung aktiv
#       - eine bestehende Diensteinheit wird entsprechend repariert und ihre Startbegrenzung zurückgesetzt
#       - WLAN-Apache wird nach der Ergänzung nur neu geladen statt neu gestartet
#       - Apache-Syntaxprüfung erhält die benötigten Laufzeitvariablen
#
# - 1.6 (2026-07-18)
#   * Optionale Wartezimmer-Schnittstelle ergänzt:
#       - separater, nur über LAN erreichbarer Samba-Share "wartezimmer-GDT"
#       - eine feste GDT-Datei pro Wartezimmer; der Dateiname bestimmt das angezeigte Ziel
#       - wartezimmer-server.php liefert pro Query die älteste Datei datensparsam aus und löscht sie sofort
#       - über WLAN werden nur die konfigurierte Namensdarstellung und das Wartezimmer übertragen
#   * Datenschutzkonfiguration wird interaktiv abgefragt:
#       - Vor- und Nachname können unabhängig vollständig oder gekürzt angezeigt werden
#       - bei Kürzung werden Buchstabenanzahl und Punkt unabhängig abgefragt
#       - Konfiguration liegt außerhalb von Webroot und Samba-Share
#   * Bestehende Installation: neuer Modus "4) Nur Wartezimmer-Schnittstelle einrichten / aktualisieren"
#   * Für wartezimmer-server.php werden keine Anwendungs- oder Apache-Zugriffslogs geschrieben
#
# - 1.5.9 (2026-06-26)
#   * Webroot-Isolation für WLAN/LAN:
#       - Fragebogen-Webroot liegt jetzt getrennt unter /srv/fragebogenpi/webroot-wlan
#       - bestehender LAN-Webroot /var/www/html bleibt als separater Share webroot-lan erhalten
#       - Samba-Shares heißen jetzt webroot-wlan und webroot-lan statt gemeinsamem WEBROOT
#   * Apache wird in zwei Instanzen getrennt:
#       - Standard-apache2 wird auf die aktuelle LAN-IP gebunden
#       - fragebogenpi-apache-wlan.service bedient nur 10.23.0.1 mit dem WLAN-Webroot
#       - WLAN-Clients können dadurch keine anderen Apache-Anwendungen wie kienzlefax/telepraxis erreichen
#
# - 1.5.8 (2026-06-26)
#   * Installer fragt jetzt, ob der Hostname neu gesetzt werden soll
#       - bei "ja" ist "fragebogenpi" der Vorschlag
#       - bei "nein" bleibt der bestehende Hostname unverändert
#   * Installer fragt jetzt, ob der WLAN-Name/SSID gesetzt werden soll
#       - bei "ja" ist "fragebogenpi" der Vorschlag
#       - bei "nein" wird eine vorhandene hostapd-SSID übernommen, soweit vorhanden
#       - das WLAN-Passwort wird weiterhin ohne zusätzliche Ja/Nein-Abfrage generiert
#   * Samba-Konfiguration wird nicht mehr vollständig überschrieben
#       - bestehende fremde Shares/Konfigurationen (z.B. kienzlefax) bleiben erhalten
#       - fragebogenpi verwaltet nur eigene globale Einstellungen und Shares über markierte Blöcke
#
# - 1.0 (2026-01-31)
#   * Initiale Version
#   * Interaktives Installationsscript für Raspberry Pi OS
#   * Installation und Konfiguration von:
#       - Apache Webserver + PHP
#       - Samba (2 Shares: GDT, PDF)
#       - hostapd + dnsmasq (isoliertes WLAN)
#   * WLAN-Access-Point "fragebogenpi" (wlan0)
#       - Eigenes Subnetz
#       - KEIN Routing ins LAN oder Internet
#       - Zugriff ausschließlich auf lokalen Webserver
#   * nftables-Firewall:
#       - wlan0: nur HTTP/HTTPS erlaubt
#       - SMB & SSH auf wlan0 gesperrt
#       - Forwarding vollständig deaktiviert
#   * Samba:
#       - Optional anonymer Zugriff oder Passwortschutz
#       - Optionaler User "fragebogenpi"
#       - Shares schreib-/lesbar
#       - SMB ausschließlich über eth0
#   * Webserver:
#       - HTTP oder optional HTTPS
#       - Self-signed Zertifikat gültig bis 2050
#   * Konsistente Dateirechte:
#       - www-data schreibberechtigt (PHP-Verarbeitung vorbereitet)
#
# - 1.1 (2026-01-31)
#   * SSH-Zugriff zusätzlich gehärtet:
#       - sshd bindet nur an LAN-IP (eth0)
#   * Hostname wird systemweit gesetzt auf "fragebogenpi"
#   * avahi-daemon aktiviert (mDNS / Bonjour)
#       - Erreichbarkeit über "fragebogenpi.local"
#   * Erweiterte Abschlussausgabe:
#       - Anzeige WLAN-Zugangsdaten
#       - Anzeige aktueller LAN-IP
#       - Anzeige MAC-Adressen (eth0 / wlan0)
#   * Hinweis zur empfohlenen DHCP-Reservation im Router
#
# - 1.1.1 (2026-01-31)
#   * Klarstellung zur Erreichbarkeit:
#       - "fragebogenpi" nur bei funktionierender Router/DNS-Auflösung
#       - "fragebogenpi.local" via mDNS (empfohlen)
#       - IP-Adresse immer gültig
#   * Abschlussausgabe entsprechend präzisiert
#   * KEINE funktionalen Änderungen gegenüber 1.1
#
# - 1.1.2 (2026-01-31)
#   * Bugfix: rand_pw() beendet Script nicht mehr (SIGPIPE/EXIT=141 mit pipefail behoben)
#       - Passwörter werden robust via python3 generiert (keine Pipefail-Falle)
#   * apt-get upgrade vor Paketinstallation ergänzt
#
# - 1.1.3 (2026-01-31)
#   * Bugfix/Kompatibilität: dhcpcd ist nicht auf allen Systemen vorhanden (z.B. Bookworm/NM)
#       - Statische IP für wlan0 wird robuster gesetzt
#       - Wenn NetworkManager aktiv ist, wird wlan0 gezielt auf "unmanaged" gesetzt, um Konflikte zu vermeiden
#
# - 1.1.4 (2026-01-31)
#   * Bugfix/Robustheit: dnsmasq kann auf manchen Systemen nicht starten (Port 53 belegt)
#       - Script prüft Port 53:
#           -> frei: dnsmasq macht DHCP + DNS-Wildcard (address=/#/AP_IP)
#           -> belegt: dnsmasq läuft DHCP-only (port=0) ohne DNS
#       - Bei dnsmasq-Fehler: automatische Ausgabe von systemctl status + journalctl -xeu
#
# - 1.1.5 (2026-01-31)
#   * Bugfix: dnsmasq "Cannot assign requested address" abgefangen (wlan0 ohne AP-IP)
#       - AP-IP wird erzwungen (iproute2) und Setup bricht mit Diagnose ab, wenn nicht möglich
#
# - 1.1.6 (2026-01-31)
#   * Bugfix: fragebogenpi-ap-ip.service Race Conditions reduziert
#       - Helper-Skript setzt AP-IP robust (rfkill unblock, warten auf wlan0, flush+add)
#       - Service mit udev-settle / After=NetworkManager
#
# - 1.2 (2026-01-31)
#   * Variante A umgesetzt: Shares liegen außerhalb des Webroots (nicht direkt per Web erreichbar)
#       - /srv/fragebogenpi/GDT und /srv/fragebogenpi/PDF
#       - PHP/Apache (www-data) hat Schreibrechte via Owner+ACL
#       - PDF ist nicht im DocumentRoot -> nicht direkt per HTTP/HTTPS abrufbar
#   * Firewall verbessert:
#       - LAN wird NICHT gefiltert (keine Einschränkungen auf eth0)
#       - Einschränkungen NUR auf wlan0: erlaubt DHCP/DNS/HTTP/HTTPS, alles andere drop
#       - Forwarding weiterhin komplett gesperrt + ip_forward=0 (kein Routing)
#   * Installer-UI verbessert:
#       - Header: "## fragebogenpi v.xxx von Thomas Kienzle"
#       - Übersichtliche Step-Blöcke mit Markierung und Status
#
# - 1.3 (2026-01-31)
#   * Strategieänderung SSH:
#       - sshd bleibt "wie normal" (lauscht auf allen Interfaces; KEIN ListenAddress mehr)
#       - SSH wird ausschließlich per Firewall auf wlan0 blockiert (LAN bleibt frei)
#   * Neuer Samba-Admin:
#       - zusätzlicher Samba-User "admin" (Passwort generiert und ausgegeben)
#       - neuer Samba-Share "WEBROOT" auf /var/www/html (nur für admin, schreib-/lesbar)
#
# - 1.4.0 (2026-01-31)
#   * PHP-Erweiterungen / Uploads:
#       - Paket php-gd wird installiert
#       - PHP-Optionen werden gesetzt:
#           upload_max_filesize=25M
#           post_max_size=250M
#           max_file_uploads=30
#           max_execution_time=120
#           max_input_time=120
#       - Umsetzung über eigene Konfigurationsdatei:
#           /etc/php/<version>/apache2/conf.d/99-fragebogenpi.ini
#         (zusätzlich auch für CLI: /etc/php/<version>/cli/conf.d/99-fragebogenpi.ini)
#   * Auto-Update:
#       - unattended-upgrades wird als Paket installiert und aktiviert
#       - 20auto-upgrades wird gesetzt (periodisch aktiv)
#   * SSH-Strategie abgesichert:
#       - Falls alte ListenAddress-Einträge vorhanden sind, werden diese entfernt.
#
# - 1.4.1 (2026-01-31)
#   * Zusätzliches Paket: php-yaml wird installiert
#   * Optional: Zugangsdaten werden (nach Rückfrage) als Textdatei ins PDF-Share geschrieben:
#       /srv/fragebogenpi/PDF/zugangsdaten_fragebogenpi_bitte_loeschen.txt
#
# - 1.5.0 (2026-02-05)
#   * Bootstrap-Download umgestellt:
#       - Dateien werden NICHT mehr einzeln (selfie.php/befund.php) hardcodiert,
#         sondern aus der Bootstrap-Liste geladen:
#           https://raw.githubusercontent.com/thomaskien/fragebogenpi/refs/heads/main/bootstrap
#       - Die Liste enthält relative Dateinamen (relativ zur Bootstrap-Datei selbst),
#         die ins Webroot heruntergeladen werden (inkl. Unterverzeichnisse).
#       - Leere Zeilen und Kommentare (#...) werden ignoriert.
#       - Pfad-Traversal (.. oder absolute Pfade) wird blockiert.
#   * Bestehende Installation erkannt:
#       - Wenn /srv/fragebogenpi existiert, fragt das Script:
#           1) Vollständige Neu-Konfiguration (setzt Passwörter neu, richtet alles neu ein)
#           2) Nur Webroot-Update (nur Bootstrap-Dateien aktualisieren; überschreibt alte Dateien)
#
# - 1.5.1 (2026-02-05)
#   * Admin-User erweitert:
#       - Linux-User "admin" erhält SSH-Zugang (Shell aktiv) und sudo-Rechte (Gruppe sudo)
#       - Linux-Passwort wird auf das generierte Admin-Passwort gesetzt
#   * Zusätzliche Windows-/Samba-User:
#       - Abfrage optionaler Userliste (z.B. für Gruppenrichtlinien)
#       - Pro User: Passwort eingeben oder generieren
#       - Eingegebene Passwörter werden NICHT ausgegeben; nur generierte werden ausgegeben/gespeichert
#   * Abschluss erweitert:
#       - Nach Ausgabe aller Zugangsdaten optionale Rückfrage zum Löschen eines Systembenutzers (Default nein, Default-User "pi")
#       - Reboot wird am Ende geplant (10 Sekunden); optionales userdel -r ist der letzte Schritt
#
# - 1.5.2 (2026-02-05)
#   * Bugfix UI: Auswahlmenü bei bestehender Installation zeigt wieder erklärende Zeilen (stderr statt stdout)
#   * Bugfix UI: Manuelle Passwort-Eingabe erzeugt keine zusätzlichen Leerzeilen mehr
#   * Bugfix Bootstrap: falscher NUL-Check entfernt; CRLF-Zeilenenden werden robust getrimmt
#
# - 1.5.3 (2026-02-05)
#   * Bugfix Samba-User: smbpasswd bekommt Passwort jetzt robust via printf (verhindert "Mismatch - password unchanged")
#   * UI: ask_password_twice() erzeugt wieder saubere Zeilenumbrüche bei verdeckter Eingabe
#   * Bestehende Installation: neues Menü "3) Nur User hinzufügen" (ohne Re-Konfiguration / ohne Webroot-Update)
#
# - 1.5.4 (2026-02-05)
#   * Bugfix Reboot: shutdown "+0.166" entfernt; Reboot jetzt robust via "sleep 10; systemctl reboot" (detached)
#   * Bugfix User-Löschung: wenn User in Benutzung, wird Löschung auf nächsten Boot verschoben (systemd oneshot)
#   * Bugfix Bootstrap: tmp_list cleanup trap von EXIT auf RETURN (kein "unbound variable" bei set -u)
#
# - 1.5.5 (2026-02-05)
#   * Bugfix Netzwerk/Internet: nftables.conf wird nicht mehr global "flush ruleset" verwenden
#       - Stattdessen eigene Tabelle "inet fragebogenpi" mit Regeln nur für wlan0
#       - LAN (eth0) bleibt vollständig unberührt -> Pi behält Internet-Konnektivität
#   * Bugfix WLAN-AP Stabilität: hostapd erhält country_code=DE + 802.11d/n (reduziert Assoziations-/Handshake-Probleme)
#   * sysctl-Anwendung konservativer: keine globale "sysctl --system" mehr (nur die zwei Forwarding-Keys werden gesetzt)
#
# - 1.5.6 (2026-02-11)
#   * Samba-User-Handling umgestellt (robust & reparierbar):
#       - Zusätzliche Windows-/Samba-User werden jetzt interaktiv EINZELN angelegt (Username → Passwort eingeben/generieren)
#       - Bestehende Samba-User können über denselben Weg repariert werden (Passwort wird sicher neu gesetzt + User enabled)
#       - Intern: Existenzprüfung via pdbedit; bei vorhandenem User wird smbpasswd ohne -a verwendet (Update statt Add)
#   * Minimal-Install "Nur User hinzufügen" erweitert:
#       - installiert samba-common-bin (pdbedit), um Updates/Reparaturen zuverlässig zu machen
#
# - 1.5.7 (2026-02-11)
#   * Fix Passwort-Handling (Samba):
#       - ask_password_twice() schreibt Prompts/Zeilenumbrüche jetzt ausschließlich auf stderr
#         und gibt NUR das Passwort auf stdout aus (verhindert eingefangene Newlines in $(...))
#       - Nach jedem smbpasswd wird ein Login-Test via smbclient gegen localhost durchgeführt
#         (früher konnten falsche Passwörter unbemerkt gesetzt werden)
# =========================
#
set -euo pipefail

# -------------------------
# Konfiguration (Defaults)
# -------------------------
AP_SSID="fragebogenpi"
HOSTNAME_FQDN="fragebogenpi"
SET_HOSTNAME="yes"

AP_INTERFACE="wlan0"
LAN_INTERFACE="eth0"

AP_SUBNET_CIDR="10.23.0.0/24"
AP_IP="10.23.0.1"
AP_DHCP_START="10.23.0.50"
AP_DHCP_END="10.23.0.150"
AP_NETMASK="255.255.255.0"

# Variante A: Shares außerhalb des Webroots
SHARE_BASE="/srv/fragebogenpi"
WEBROOT_LAN="/var/www/html"
WEBROOT_WLAN="${SHARE_BASE}/webroot-wlan"
WEBROOT="${WEBROOT_WLAN}"  # fragebogenpi-App: nur für die isolierte WLAN-Apache-Instanz
SHARE_GDT="${SHARE_BASE}/GDT"
SHARE_PDF="${SHARE_BASE}/PDF"
SHARE_FORMULARE="${SHARE_BASE}/formulare"
SHARE_WAITING_ROOM="${SHARE_BASE}/wartezimmer-GDT"
CRED_FILE="${SHARE_PDF}/zugangsdaten_fragebogenpi_bitte_loeschen.txt"

# Wartezimmer-Schnittstelle
WAITING_ROOM_CONFIG="/etc/fragebogenpi/wartezimmer-config.php"
WAITING_ROOM_LOCK="${SHARE_BASE}/.wartezimmer-server.lock"
WAITING_ROOM_SERVER="${WEBROOT_WLAN}/wartezimmer-server.php"
WAITING_ROOM_SERVER_URL="https://raw.githubusercontent.com/thomaskien/fragebogenpi/refs/heads/main/wartezimmer-server.php"
WAITING_ROOM_ENABLED="no"
WAITING_SHORTEN_FIRST="yes"
WAITING_FIRST_LETTERS="1"
WAITING_FIRST_DOT="yes"
WAITING_SHORTEN_LAST="yes"
WAITING_LAST_LETTERS="2"
WAITING_LAST_DOT="yes"

# Tablet-/Formularbetrieb
TABLET_COUNT_FILE="/etc/fragebogenpi/tablet-count"
TABLET_COUNT="1"

# Samba-User
SAMBA_USER="fragebogenpi"   # optional (für GDT/PDF, wenn Passwortschutz gewählt)
ADMIN_USER="admin"          # immer vorhanden für webroot-wlan/webroot-lan Shares

# HTTPS (optional)
SSL_DIR="/etc/ssl/fragebogenpi"
SSL_KEY="${SSL_DIR}/fragebogenpi.key"
SSL_CRT="${SSL_DIR}/fragebogenpi.crt"

# AP IP helper/service
AP_IP_SERVICE="/etc/systemd/system/fragebogenpi-ap-ip.service"
AP_IP_HELPER="/usr/local/sbin/fragebogenpi-ap-ip.sh"

# Apache-Isolation: LAN-Instanz + separate WLAN-Instanz
APACHE_WLAN_DIR="/etc/fragebogenpi/apache-wlan"
APACHE_WLAN_CONF="${APACHE_WLAN_DIR}/apache2.conf"
APACHE_WLAN_SERVICE="/etc/systemd/system/fragebogenpi-apache-wlan.service"
APACHE_WLAN_RUN_DIR="/run/fragebogenpi-apache-wlan"
APACHE_WLAN_LOG_DIR="/var/log/apache2"
APACHE_LAN_BIND_HELPER="/usr/local/sbin/fragebogenpi-apache-lan-bind.sh"
APACHE_LAN_BIND_SERVICE="/etc/systemd/system/fragebogenpi-apache-lan-bind.service"
APACHE_LAN_DROPIN_DIR="/etc/systemd/system/apache2.service.d"
APACHE_LAN_DROPIN="${APACHE_LAN_DROPIN_DIR}/10-fragebogenpi-lan-bind.conf"

# Bootstrap-Dateiliste (relative Dateinamen)
BOOTSTRAP_URL="https://raw.githubusercontent.com/thomaskien/fragebogenpi/refs/heads/main/bootstrap"

# PHP Settings (gewünscht)
PHP_UPLOAD_MAX="25M"
PHP_POST_MAX="250M"
PHP_MAX_UPLOADS="30"
PHP_MAX_EXEC="120"
PHP_MAX_INPUT="120"

# Delete-user-on-boot helper
DELETE_USER_MARKER="/etc/fragebogenpi/delete_user"
DELETE_USER_HELPER="/usr/local/sbin/fragebogenpi-delete-user.sh"
DELETE_USER_SERVICE="/etc/systemd/system/fragebogenpi-delete-user.service"

# WLAN country (hostapd)
WIFI_COUNTRY="DE"

# -------------------------
# UI / Logging
# -------------------------
VERSION="1.6.4"
STEP_NO=0

banner() {
  echo
  echo "## fragebogenpi v${VERSION} von Thomas Kienzle"
  echo "##"
  echo "## Starte installation..."
  echo
}

log()  { echo -e "[fragebogenpi] $*"; }
warn() { echo -e "[fragebogenpi][WARN] $*" >&2; }
die()  { echo -e "[fragebogenpi][ERROR] $*" >&2; exit 1; }

step() {
  STEP_NO=$((STEP_NO+1))
  echo
  echo "======================================================"
  echo "== Schritt ${STEP_NO}: $*"
  echo "======================================================"
}

ok() {
  echo "[OK] $*"
}

# -------------------------
# Helper
# -------------------------
require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Bitte als root ausführen: sudo bash fragebogenpi.sh"
  fi
}

rand_pw() {
  python3 - <<'PY'
import secrets
alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
print("".join(secrets.choice(alphabet) for _ in range(16)), end="")
PY
}

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    cp -a "$f" "${f}.bak.$(date +%Y%m%d_%H%M%S)"
  fi
}

ask_yes_no() {
  local prompt="$1"
  local default="$2"  # "y" oder "n"
  local answer=""
  while true; do
    if [[ "$default" == "y" ]]; then
      read -r -p "$prompt [Y/n]: " answer
      answer="${answer:-Y}"
    else
      read -r -p "$prompt [y/N]: " answer
      answer="${answer:-N}"
    fi
    case "${answer,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) echo "Bitte y oder n eingeben." ;;
    esac
  done
}

trim_value() {
  local value="$1"
  value="${value%$'\r'}"
  value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"
  printf '%s' "$value"
}

current_system_hostname() {
  local current=""
  current="$(hostname 2>/dev/null || true)"
  current="$(trim_value "$current")"
  if [[ -z "$current" ]] && [[ -f /etc/hostname ]]; then
    current="$(head -n 1 /etc/hostname 2>/dev/null || true)"
    current="$(trim_value "$current")"
  fi
  printf '%s' "$current"
}

current_hostapd_ssid() {
  local hostapd_conf="/etc/hostapd/hostapd.conf"
  if [[ -f "$hostapd_conf" ]]; then
    awk -F= '/^ssid=/ {sub(/^ssid=/, ""); print; exit}' "$hostapd_conf" 2>/dev/null || true
  fi
}

is_valid_hostname() {
  local h="$1"
  [[ "$h" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

is_valid_ssid() {
  local ssid="$1"
  [[ -n "$ssid" ]] && (( ${#ssid} <= 32 ))
}

ask_hostname_setup() {
  local current desired
  current="$(current_system_hostname)"
  [[ -n "$current" ]] || current="${HOSTNAME_FQDN}"

  if ask_yes_no "Hostname setzen/ändern? (aktuell: ${current})" "y"; then
    while true; do
      read -r -p "Hostname [${HOSTNAME_FQDN}]: " desired
      desired="$(trim_value "$desired")"
      desired="${desired:-$HOSTNAME_FQDN}"
      if is_valid_hostname "$desired"; then
        HOSTNAME_FQDN="$desired"
        SET_HOSTNAME="yes"
        return 0
      fi
      echo "Bitte einen gültigen Hostname eingeben (Buchstaben, Zahlen, Bindestrich; 1-63 Zeichen)."
    done
  else
    HOSTNAME_FQDN="$current"
    SET_HOSTNAME="no"
    log "Hostname bleibt unverändert: ${HOSTNAME_FQDN}"
  fi
}

ask_ap_ssid_setup() {
  local current desired
  current="$(current_hostapd_ssid)"

  if [[ -n "$current" ]]; then
    if ! ask_yes_no "WLAN-Name/SSID setzen/ändern? (aktuell: ${current})" "y"; then
      AP_SSID="$current"
      log "WLAN-SSID bleibt unverändert: ${AP_SSID}"
      return 0
    fi
  else
    if ! ask_yes_no "WLAN-Name/SSID setzen/ändern?" "y"; then
      warn "Keine bestehende hostapd-SSID gefunden – verwende Standard '${AP_SSID}'."
      return 0
    fi
  fi

  while true; do
    read -r -p "WLAN-Name/SSID [${AP_SSID}]: " desired
    desired="$(trim_value "$desired")"
    desired="${desired:-$AP_SSID}"
    if is_valid_ssid "$desired"; then
      AP_SSID="$desired"
      return 0
    fi
    echo "Bitte eine nicht-leere SSID mit maximal 32 Zeichen eingeben."
  done
}

ask_positive_integer_without_maximum() {
  local prompt="$1"
  local default="$2"
  local value=""

  while true; do
    read -r -p "${prompt} [${default}]: " value
    value="$(trim_value "$value")"
    value="${value:-$default}"
    if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
      printf '%s' "$value"
      return 0
    fi
    echo "Bitte eine positive ganze Zahl eingeben." >&2
  done
}

load_tablet_count() {
  local value=""
  if [[ -f "$TABLET_COUNT_FILE" ]]; then
    value="$(tr -d '\r\n' < "$TABLET_COUNT_FILE" 2>/dev/null || true)"
  fi
  if [[ "$value" =~ ^[1-9]$ ]]; then
    TABLET_COUNT="$value"
  fi
}

ask_tablet_count() {
  load_tablet_count

  local answer=""
  while true; do
    read -r -p "Wie viele Tablets sollen verwendet werden? [${TABLET_COUNT}]: " answer
    answer="$(trim_value "$answer")"
    answer="${answer:-$TABLET_COUNT}"
    if [[ "$answer" =~ ^[1-9]$ ]]; then
      TABLET_COUNT="$answer"
      return 0
    fi
    echo "Bitte eine Zahl von 1 bis 9 eingeben (GDT-Dateinamen maximal 12 Zeichen)." >&2
  done
}

save_tablet_count() {
  mkdir -p "$(dirname "$TABLET_COUNT_FILE")"
  printf '%s\n' "$TABLET_COUNT" > "$TABLET_COUNT_FILE"
  chmod 0644 "$TABLET_COUNT_FILE"
}

ask_waiting_room_privacy_config() {
  step "Datenschutzkonfiguration für Wartezimmer-Aufrufe"

  if ask_yes_no "Vorname kürzen?" "y"; then
    WAITING_SHORTEN_FIRST="yes"
    WAITING_FIRST_LETTERS="$(ask_positive_integer_without_maximum "Anzahl der angezeigten Buchstaben des Vornamens" "1")"
    if ask_yes_no "Punkt nach dem gekürzten Vornamen anzeigen?" "y"; then
      WAITING_FIRST_DOT="yes"
    else
      WAITING_FIRST_DOT="no"
    fi
  else
    WAITING_SHORTEN_FIRST="no"
    WAITING_FIRST_DOT="no"
  fi

  if ask_yes_no "Nachname kürzen?" "y"; then
    WAITING_SHORTEN_LAST="yes"
    WAITING_LAST_LETTERS="$(ask_positive_integer_without_maximum "Anzahl der angezeigten Buchstaben des Nachnamens" "2")"
    if ask_yes_no "Punkt nach dem gekürzten Nachnamen anzeigen?" "y"; then
      WAITING_LAST_DOT="yes"
    else
      WAITING_LAST_DOT="no"
    fi
  else
    WAITING_SHORTEN_LAST="no"
    WAITING_LAST_DOT="no"
  fi

  ok "Datenschutzkonfiguration übernommen"
}

ask_choice_http_https() {
  local answer=""
  while true; do
    read -r -p "Webserver: Nur HTTP (1) oder HTTP+HTTPS (2)? [1/2]: " answer
    case "$answer" in
      1) echo "http"; return 0 ;;
      2) echo "https"; return 0 ;;
      *) echo "Bitte 1 oder 2 eingeben." ;;
    esac
  done
}

ask_choice_existing_install() {
  local answer=""
  echo >&2
  echo "[fragebogenpi] Es wurde eine bestehende Installation gefunden: ${SHARE_BASE}" >&2
  echo "Hinweis: Auswahl 2 überschreibt Dateien im isolierten WLAN-Webroot (Programme/Bootstrap), sonst nichts." >&2
  echo "Was soll ich tun?" >&2
  echo "  1) Vollständige Neu-Konfiguration (setzt Passwörter neu, richtet Dienste/Firewall/Samba/AP/PHP neu ein)" >&2
  echo "  2) Nur Webroot-Update (lädt/aktualisiert nur die Programme im WLAN-Webroot; bestehende Dateien werden überschrieben)" >&2
  echo "  3) Nur User hinzufügen (legt/aktualisiert zusätzliche Windows-/Samba-User; sonst keine Änderungen)" >&2
  echo "  4) Nur Wartezimmer-Schnittstelle einrichten / aktualisieren" >&2
  echo "  5) Nur Tablet-/Formularbetrieb einrichten / aktualisieren" >&2
  while true; do
    read -r -p "Auswahl [1/2/3/4/5]: " answer
    case "$answer" in
      1) echo "full"; return 0 ;;
      2) echo "webroot"; return 0 ;;
      3) echo "users"; return 0 ;;
      4) echo "waiting"; return 0 ;;
      5) echo "tablets"; return 0 ;;
      *) echo "Bitte 1, 2, 3, 4 oder 5 eingeben." >&2 ;;
    esac
  done
}

# Wichtig: Diese Funktion darf NUR das Passwort auf stdout ausgeben.
# Alle Prompts/Zeilenumbrüche/Fehltexte -> stderr, sonst landen Newlines in pw="$(...)".
ask_password_twice() {
  local prompt="$1"
  local p1="" p2=""

  while true; do
    read -r -s -p "${prompt}: " p1 >&2
    printf '\n' >&2
    read -r -s -p "${prompt} (Wiederholung): " p2 >&2
    printf '\n' >&2

    # CR entfernen (z.B. serielle Konsole / CRLF)
    p1="${p1%$'\r'}"
    p2="${p2%$'\r'}"

    [[ -n "$p1" ]] || { echo "Passwort darf nicht leer sein." >&2; continue; }
    if [[ "$p1" == "$p2" ]]; then
      printf '%s' "$p1"
      return 0
    fi
    echo "Passwörter stimmen nicht überein. Bitte erneut." >&2
  done
}

get_iface_ipv4() {
  local iface="$1"
  ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true
}

get_iface_mac() {
  local iface="$1"
  cat "/sys/class/net/${iface}/address" 2>/dev/null || true
}

systemd_unit_exists() {
  systemctl list-unit-files --type=service | awk '{print $1}' | grep -qx "$1"
}

port_in_use() {
  local port="$1"
  if ss -H -lntu 2>/dev/null | awk '{print $5}' | grep -Eq "(:|\\])${port}\$"; then
    return 0
  fi
  return 1
}

print_service_debug_and_die() {
  local svc="$1"
  warn "Service '${svc}' konnte nicht gestartet werden."
  warn "----- systemctl status ${svc} -----"
  systemctl --no-pager -l status "${svc}" || true
  warn "----- journalctl -xeu ${svc} (letzte 160 Zeilen) -----"
  journalctl --no-pager -xeu "${svc}" | tail -n 160 || true
  die "Abbruch, bitte Logausgabe oben prüfen."
}

ensure_linux_user() {
  local u="$1"
  local shell="${2:-/usr/sbin/nologin}"
  if ! id -u "$u" >/dev/null 2>&1; then
    useradd -m -s "$shell" "$u"
  else
    if [[ -n "$shell" ]] && command -v usermod >/dev/null 2>&1; then
      usermod -s "$shell" "$u" >/dev/null 2>&1 || true
    fi
  fi
}

ensure_command() {
  local cmd="$1"
  local pkg="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "Fehlender Befehl '${cmd}' – installiere Paket '${pkg}'..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
  fi
}

sanitize_relpath_or_die() {
  local p="$1"
  [[ -n "$p" ]] || die "Bootstrap-Liste enthält eine leere Zeile nach Trimming (sollte nicht passieren)."
  [[ "$p" != /* ]] || die "Unsicherer Pfad in Bootstrap-Liste (absolut): '$p'"
  if echo "$p" | grep -Eq '(^|/)\.\.(/|$)'; then
    die "Unsicherer Pfad in Bootstrap-Liste (..): '$p'"
  fi
}

schedule_reboot_10s() {
  log "Reboot in 10 Sekunden..."
  nohup bash -c 'sleep 10; systemctl reboot >/dev/null 2>&1 || /sbin/reboot >/dev/null 2>&1 || reboot >/dev/null 2>&1' >/dev/null 2>&1 &
}

install_delete_user_on_boot() {
  local del_user="$1"

  mkdir -p /etc/fragebogenpi
  echo "$del_user" > "$DELETE_USER_MARKER"
  chmod 0600 "$DELETE_USER_MARKER"

  backup_file "$DELETE_USER_HELPER"
  cat > "$DELETE_USER_HELPER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

MARKER="/etc/fragebogenpi/delete_user"
SERVICE="fragebogenpi-delete-user.service"

[[ -f "$MARKER" ]] || exit 0

u="$(cat "$MARKER" | tr -d '\r' | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"
if [[ -z "$u" ]] || [[ "$u" == "root" ]]; then
  rm -f "$MARKER" || true
  systemctl disable "$SERVICE" >/dev/null 2>&1 || true
  exit 0
fi

pkill -u "$u" >/dev/null 2>&1 || true
sleep 0.5
userdel -r "$u" >/dev/null 2>&1 || true

rm -f "$MARKER" || true
systemctl disable "$SERVICE" >/dev/null 2>&1 || true
EOF
  chmod 0755 "$DELETE_USER_HELPER"

  backup_file "$DELETE_USER_SERVICE"
  cat > "$DELETE_USER_SERVICE" <<EOF
[Unit]
Description=fragebogenpi: delete user once after boot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=${DELETE_USER_HELPER}

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable fragebogenpi-delete-user.service >/dev/null 2>&1 || true
}

ensure_samba_running_for_test() {
  # konservativ: nur starten, wenn systemctl existiert; Fehler ignorieren (Test entscheidet)
  if command -v systemctl >/dev/null 2>&1; then
    systemctl start smbd >/dev/null 2>&1 || true
  fi
}

samba_login_test() {
  local u="$1" pw="$2"
  ensure_command smbclient smbclient
  ensure_samba_running_for_test

  # Auth-Test: Share-Liste auf localhost anfordern
  smbclient -L 127.0.0.1 -U "${u}%${pw}" -m SMB3 >/dev/null 2>&1
}

# Samba helpers (existence / robust set)
samba_user_exists() {
  local u="$1"
  pdbedit -L 2>/dev/null | awk -F: '{print $1}' | grep -qx "$u"
}

set_samba_password_add_or_update() {
  local u="$1"
  local pw="$2"

  if samba_user_exists "$u"; then
    printf '%s\n' "$pw" "$pw" | smbpasswd -s "$u"
  else
    printf '%s\n' "$pw" "$pw" | smbpasswd -a -s "$u"
  fi

  smbpasswd -e "$u" >/dev/null 2>&1 || true

  # Pflicht: Login-Test direkt nach dem Setzen
  if ! samba_login_test "$u" "$pw"; then
    die "Samba-Login-Test fehlgeschlagen für User '${u}'. Passwort wurde vermutlich nicht korrekt gesetzt."
  fi
}

# Globals for extra users (needed for output/cred file)
declare -a EXTRA_USERS_LIST=()
declare -a EXTRA_USERS_PW=()
declare -a EXTRA_USERS_MODE=()

manage_users_interactive() {
  local headline="$1"

  step "${headline}"

  ensure_command smbpasswd samba
  ensure_command pdbedit samba-common-bin
  ensure_command smbclient smbclient

  EXTRA_USERS_LIST=()
  EXTRA_USERS_PW=()
  EXTRA_USERS_MODE=()

  echo "User einzeln anlegen/aktualisieren:"
  echo "  - Username eingeben (leer = fertig)"
  echo "  - Danach Passwort eingeben oder generieren"
  echo "  - Existiert der User bereits in Samba, wird das Passwort sicher aktualisiert (Reparatur)"
  echo "  - Nach dem Setzen erfolgt ein Login-Test (smbclient gegen localhost)"
  echo

  while true; do
    local u=""
    read -r -p "Username (leer = fertig): " u
    u="$(echo "$u" | sed -e 's/\r$//' -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"

    [[ -n "$u" ]] || break

    if [[ "$u" == "root" ]]; then
      echo "root ist nicht erlaubt."
      echo
      continue
    fi

    ensure_linux_user "$u" "/usr/sbin/nologin"

    local choice=""
    while true; do
      read -r -p "User '${u}': Passwort eingeben (1) oder generieren (2)? [2]: " choice
      choice="${choice:-2}"
      case "$choice" in
        1|2) break ;;
        *) echo "Bitte 1 oder 2 eingeben." ;;
      esac
    done

    local pw="" mode=""
    if [[ "$choice" == "1" ]]; then
      pw="$(ask_password_twice "Passwort für '${u}'")"
      mode="manual"
    else
      pw="$(rand_pw)"
      mode="generated"
    fi

    log "Setze Samba-Passwort für '${u}' (neu oder Update) ..."
    set_samba_password_add_or_update "$u" "$pw"
    ok "User '${u}' gesetzt/aktualisiert (Samba enabled + Login-Test OK)"

    EXTRA_USERS_LIST+=("$u")
    EXTRA_USERS_PW+=("$pw")
    EXTRA_USERS_MODE+=("$mode")

    echo
  done

  ok "User-Eingabe abgeschlossen"
}

# -------------------------
# Installation
# -------------------------
install_packages_full() {
  step "System aktualisieren und Pakete installieren"
  log "Paketlisten aktualisieren & System upgraden..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

  log "Installiere benötigte Pakete..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apache2 php libapache2-mod-php php-gd php-yaml \
    samba samba-common-bin smbclient \
    hostapd dnsmasq \
    nftables \
    acl openssl \
    avahi-daemon \
    python3 \
    curl \
    unattended-upgrades \
    sudo \
    iw

  ok "Pakete installiert (inkl. php-gd, php-yaml, curl, unattended-upgrades, sudo, iw, samba-common-bin, smbclient)"
}

install_packages_webroot_only() {
  step "Minimal: Tools für Webroot-Update sicherstellen"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl
  ok "curl ist verfügbar"
}

install_packages_users_only() {
  step "Minimal: Tools für User-Setup sicherstellen"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y samba samba-common-bin smbclient
  ok "samba + samba-common-bin + smbclient ist verfügbar (smbpasswd/pdbedit/smbclient)"
}

install_packages_waiting_room_only() {
  step "Minimal: Pakete für die Wartezimmer-Schnittstelle sicherstellen"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl samba samba-common-bin php acl
  ok "curl, Samba, PHP und ACL-Werkzeuge sind verfügbar"
}

set_hostname() {
  step "Hostname setzen und mDNS aktivieren"

  if [[ "$SET_HOSTNAME" == "yes" ]]; then
    log "Setze Hostname auf '${HOSTNAME_FQDN}'..."
    backup_file /etc/hostname
    backup_file /etc/hosts

    if command -v hostnamectl >/dev/null 2>&1; then
      hostnamectl set-hostname "${HOSTNAME_FQDN}"
    else
      echo "${HOSTNAME_FQDN}" > /etc/hostname
      hostname "${HOSTNAME_FQDN}" || true
    fi

    if grep -qE '^127\.0\.1\.1[[:space:]]+' /etc/hosts 2>/dev/null; then
      sed -i -E "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1 ${HOSTNAME_FQDN}/" /etc/hosts
    else
      echo "127.0.1.1 ${HOSTNAME_FQDN}" >> /etc/hosts
    fi
  else
    log "Hostname bleibt unverändert (${HOSTNAME_FQDN})."
  fi

  systemctl enable --now avahi-daemon >/dev/null 2>&1 || true
  systemctl restart avahi-daemon >/dev/null 2>&1 || true

  ok "Hostname/mDNS konfiguriert"
}

setup_share_dirs() {
  local waiting_room_enabled="${1:-no}"
  step "Share-Verzeichnisse (Variante A) erstellen und Rechte setzen"
  log "Erstelle Share-Verzeichnisse außerhalb des Webroots: ${SHARE_BASE}"
  mkdir -p "$SHARE_GDT" "$SHARE_PDF" "$SHARE_FORMULARE"
  if [[ "$waiting_room_enabled" == "yes" ]]; then
    mkdir -p "$SHARE_WAITING_ROOM"
  fi

  chown -R www-data:www-data "$SHARE_BASE"
  chmod -R 2775 "$SHARE_BASE"

  setfacl -R -m u:www-data:rwx "$SHARE_GDT" "$SHARE_PDF" "$SHARE_FORMULARE" || true
  setfacl -R -d -m u:www-data:rwx "$SHARE_GDT" "$SHARE_PDF" "$SHARE_FORMULARE" || true
  if [[ "$waiting_room_enabled" == "yes" ]]; then
    setfacl -R -m u:www-data:rwx "$SHARE_WAITING_ROOM" || true
    setfacl -R -d -m u:www-data:rwx "$SHARE_WAITING_ROOM" || true
  fi

  ok "Shares liegen außerhalb des Webroots (nicht direkt per Web erreichbar)"
}

setup_formulare_dir_only() {
  step "Formularverzeichnis vorbereiten"
  mkdir -p "$SHARE_FORMULARE"
  chown www-data:www-data "$SHARE_FORMULARE" || true
  chmod 2775 "$SHARE_FORMULARE"
  setfacl -m u:www-data:rwx "$SHARE_FORMULARE" || true
  setfacl -d -m u:www-data:rwx "$SHARE_FORMULARE" || true
  ok "Formularverzeichnis vorbereitet: ${SHARE_FORMULARE}"
}

setup_webroot_perms() {
  step "Webroots vorbereiten (WLAN isoliert, LAN bestehend)"

  mkdir -p "$WEBROOT_WLAN" "$WEBROOT_LAN"

  chown -R www-data:www-data "$WEBROOT_WLAN"
  chmod -R 2775 "$WEBROOT_WLAN"
  setfacl -R -m u:www-data:rwx "$WEBROOT_WLAN" || true
  setfacl -R -d -m u:www-data:rwx "$WEBROOT_WLAN" || true

  # Den bestehenden LAN-Webroot nicht rekursiv verändern: dort können andere Anwendungen liegen.
  chmod 2775 "$WEBROOT_LAN" || true
  setfacl -m u:www-data:rwx "$WEBROOT_LAN" || true
  setfacl -d -m u:www-data:rwx "$WEBROOT_LAN" || true

  ok "WLAN-Webroot ist isoliert vorbereitet; LAN-Webroot bleibt erhalten"
}

write_samba_global_block() {
  cat <<EOF
# --- fragebogenpi GLOBAL BEGIN ---
   security = user
   map to guest = Bad User

   # SMB nur im LAN anbieten (${LAN_INTERFACE})
   interfaces = lo ${LAN_INTERFACE}
   bind interfaces only = yes

   server min protocol = SMB2
   server max protocol = SMB3

   create mask = 0664
   directory mask = 2775
   force create mode = 0664
   force directory mode = 2775
# --- fragebogenpi GLOBAL END ---
EOF
}

strip_samba_managed_blocks() {
  local src="$1"
  local dst="$2"

  awk '
    /^# --- fragebogenpi GLOBAL BEGIN ---$/ { skip=1; next }
    /^# --- fragebogenpi GLOBAL END ---$/ { skip=0; next }
    /^# --- fragebogenpi SHARES BEGIN ---$/ { skip=1; next }
    /^# --- fragebogenpi SHARES END ---$/ { skip=0; next }
    /^# --- fragebogenpi WARTEZIMMER SHARE BEGIN ---$/ { skip=1; next }
    /^# --- fragebogenpi WARTEZIMMER SHARE END ---$/ { skip=0; next }
    /^# --- fragebogenpi FORMULARE SHARE BEGIN ---$/ { skip=1; next }
    /^# --- fragebogenpi FORMULARE SHARE END ---$/ { skip=0; next }
    skip != 1 { print }
  ' "$src" > "$dst"
}

strip_samba_share_sections() {
  local src="$1"
  local dst="$2"

  awk '
    BEGIN {
      drop["gdt"]=1
      drop["pdf"]=1
      drop["webroot"]=1
      drop["webroot-wlan"]=1
      drop["webroot-lan"]=1
      drop["formulare"]=1
      drop["wartezimmer-gdt"]=1
      skip=0
    }
    /^\[[^]]+\][[:space:]]*$/ {
      section=$0
      gsub(/^\[/, "", section)
      gsub(/\][[:space:]]*$/, "", section)
      lower=tolower(section)
      skip=(lower in drop) ? 1 : 0
    }
    skip != 1 { print }
  ' "$src" > "$dst"
}

insert_samba_global_block() {
  local src="$1"
  local block_file="$2"
  local dst="$3"

  if ! grep -qiE '^\[global\][[:space:]]*$' "$src"; then
    {
      echo "[global]"
      cat "$block_file"
      echo
      cat "$src"
    } > "$dst"
    return 0
  fi

  awk -v block_file="$block_file" '
    function print_block(   line) {
      while ((getline line < block_file) > 0) {
        print line
      }
      close(block_file)
    }
    BEGIN {
      in_global=0
      inserted=0
    }
    /^\[[^]]+\][[:space:]]*$/ {
      if (in_global == 1 && inserted == 0) {
        print_block()
        inserted=1
      }
      if (tolower($0) ~ /^\[global\][[:space:]]*$/) {
        in_global=1
      } else {
        in_global=0
      }
      print
      next
    }
    { print }
    END {
      if (in_global == 1 && inserted == 0) {
        print_block()
      }
    }
  ' "$src" > "$dst"
}

write_samba_shares_block() {
  local use_auth="$1"
  local valid_users_gdtpdf="$2"

  echo
  echo "# --- fragebogenpi SHARES BEGIN ---"

  if [[ "$use_auth" == "no" ]]; then
    cat <<EOF
[GDT]
   path = ${SHARE_GDT}
   browseable = yes
   read only = no
   guest ok = yes
   force user = www-data
   force group = www-data

[PDF]
   path = ${SHARE_PDF}
   browseable = yes
   read only = no
   guest ok = yes
   force user = www-data
   force group = www-data
EOF
  else
    cat <<EOF
[GDT]
   path = ${SHARE_GDT}
   browseable = yes
   read only = no
   guest ok = no
   valid users = ${valid_users_gdtpdf}
   force user = www-data
   force group = www-data

[PDF]
   path = ${SHARE_PDF}
   browseable = yes
   read only = no
   guest ok = no
   valid users = ${valid_users_gdtpdf}
   force user = www-data
   force group = www-data
EOF
  fi

  cat <<EOF

[formulare]
   path = ${SHARE_FORMULARE}
   browseable = yes
   read only = no
   guest ok = no
   valid users = ${ADMIN_USER}
   force user = www-data
   force group = www-data

[webroot-wlan]
   path = ${WEBROOT_WLAN}
   browseable = yes
   read only = no
   guest ok = no
   valid users = ${ADMIN_USER}
   force user = www-data
   force group = www-data

[webroot-lan]
   path = ${WEBROOT_LAN}
   browseable = yes
   read only = no
   guest ok = no
   valid users = ${ADMIN_USER}
   force user = www-data
   force group = www-data
# --- fragebogenpi SHARES END ---
EOF
}

write_samba_waiting_room_block() {
  local use_auth="$1"
  local valid_users="$2"

  echo
  echo "# --- fragebogenpi WARTEZIMMER SHARE BEGIN ---"
  if [[ "$use_auth" == "yes" ]]; then
    cat <<EOF
[wartezimmer-GDT]
   path = ${SHARE_WAITING_ROOM}
   browseable = yes
   read only = no
   guest ok = no
   valid users = ${valid_users}
   force user = www-data
   force group = www-data
# --- fragebogenpi WARTEZIMMER SHARE END ---
EOF
  else
    cat <<EOF
[wartezimmer-GDT]
   path = ${SHARE_WAITING_ROOM}
   browseable = yes
   read only = no
   guest ok = yes
   force user = www-data
   force group = www-data
# --- fragebogenpi WARTEZIMMER SHARE END ---
EOF
  fi
}

setup_samba() {
  step "Samba konfigurieren (nur LAN; optionale Wartezimmer-Schnittstelle)"
  local use_auth="$1"          # "yes"|"no"
  local samba_pw="$2"          # wenn use_auth=yes
  local admin_pw="$3"          # immer
  local extra_users_space="$4" # space-separated usernames (optional)
  local waiting_room_enabled="${5:-no}"

  log "Konfiguriere Samba..."

  local smbconf="/etc/samba/smb.conf"
  mkdir -p "$(dirname "$smbconf")"
  if [[ ! -f "$smbconf" ]]; then
    printf '[global]\n' > "$smbconf"
  fi
  backup_file "$smbconf"

  local valid_users_gdtpdf=""
  if [[ "$use_auth" == "yes" ]]; then
    valid_users_gdtpdf="${SAMBA_USER}"
    if [[ -n "${extra_users_space// }" ]]; then
      valid_users_gdtpdf="${valid_users_gdtpdf} ${extra_users_space}"
    fi
  fi

  local tmp_strip tmp_shares tmp_global tmp_final global_block
  tmp_strip="$(mktemp)"
  tmp_shares="$(mktemp)"
  tmp_global="$(mktemp)"
  tmp_final="$(mktemp)"
  global_block="$(mktemp)"
  trap 'rm -f "$tmp_strip" "$tmp_shares" "$tmp_global" "$tmp_final" "$global_block"; trap - RETURN' RETURN

  write_samba_global_block > "$global_block"
  strip_samba_managed_blocks "$smbconf" "$tmp_strip"
  strip_samba_share_sections "$tmp_strip" "$tmp_shares"
  insert_samba_global_block "$tmp_shares" "$global_block" "$tmp_global"
  {
    cat "$tmp_global"
    write_samba_shares_block "$use_auth" "$valid_users_gdtpdf"
    if [[ "$waiting_room_enabled" == "yes" ]]; then
      write_samba_waiting_room_block "$use_auth" "$valid_users_gdtpdf"
    fi
  } > "$tmp_final"
  cat "$tmp_final" > "$smbconf"

  if [[ "$use_auth" == "yes" ]]; then
    log "Lege Benutzer '${SAMBA_USER}' an (falls nicht vorhanden) und setze Samba-Passwort..."
    ensure_linux_user "${SAMBA_USER}" "/usr/sbin/nologin"
    set_samba_password_add_or_update "${SAMBA_USER}" "${samba_pw}"
  fi

  log "Lege Admin-Benutzer '${ADMIN_USER}' an (falls nicht vorhanden), setze Linux+Samba-Passwort und gebe sudo..."
  ensure_linux_user "${ADMIN_USER}" "/bin/bash"

  if getent group sudo >/dev/null 2>&1; then
    usermod -aG sudo "${ADMIN_USER}" >/dev/null 2>&1 || true
  fi

  echo "${ADMIN_USER}:${admin_pw}" | chpasswd
  set_samba_password_add_or_update "${ADMIN_USER}" "${admin_pw}"

  systemctl enable --now smbd nmbd || true
  systemctl restart smbd nmbd || true

  ok "Samba läuft (nur LAN/eth0). Admin hat SSH+sudo."
}

strip_samba_waiting_room_share() {
  local src="$1"
  local dst="$2"

  awk '
    /^# --- fragebogenpi WARTEZIMMER SHARE BEGIN ---$/ { skip_block=1; next }
    /^# --- fragebogenpi WARTEZIMMER SHARE END ---$/ { skip_block=0; next }
    skip_block == 1 { next }
    /^\[[^]]+\][[:space:]]*$/ {
      section=$0
      gsub(/^\[/, "", section)
      gsub(/\][[:space:]]*$/, "", section)
      skip_section=(tolower(section) == "wartezimmer-gdt") ? 1 : 0
      if (skip_section == 1) next
    }
    skip_section != 1 { print }
  ' "$src" > "$dst"
}

read_samba_gdt_setting() {
  local smbconf="$1"
  local setting="$2"

  awk -v wanted="$setting" '
    /^\[[^]]+\][[:space:]]*$/ {
      section=$0
      gsub(/^\[/, "", section)
      gsub(/\][[:space:]]*$/, "", section)
      in_gdt=(tolower(section) == "gdt") ? 1 : 0
      next
    }
    in_gdt == 1 && index($0, "=") > 0 {
      key=$0
      sub(/=.*/, "", key)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (tolower(key) == tolower(wanted)) {
        value=$0
        sub(/^[^=]*=/, "", value)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        print value
        exit
      }
    }
  ' "$smbconf"
}

setup_samba_waiting_room_only() {
  step "Samba-Share wartezimmer-GDT ergänzen / aktualisieren"

  local smbconf="/etc/samba/smb.conf"
  [[ -f "$smbconf" ]] || die "Samba-Konfiguration fehlt: ${smbconf}. Bitte Vollinstallation verwenden."

  local guest_setting valid_users use_auth
  guest_setting="$(read_samba_gdt_setting "$smbconf" "guest ok")"
  valid_users="$(read_samba_gdt_setting "$smbconf" "valid users")"
  use_auth="yes"
  case "${guest_setting,,}" in
    yes|true|1) use_auth="no" ;;
  esac

  if [[ "$use_auth" == "yes" ]] && [[ -z "$valid_users" ]]; then
    die "Zugriffsregel des bestehenden GDT-Shares konnte nicht übernommen werden. Bitte Vollinstallation verwenden."
  fi

  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"; trap - RETURN' RETURN

  strip_samba_waiting_room_share "$smbconf" "$tmp"
  write_samba_waiting_room_block "$use_auth" "$valid_users" >> "$tmp"

  testparm -s "$tmp" >/dev/null || die "Erzeugte Samba-Konfiguration ist ungültig."
  backup_file "$smbconf"
  cat "$tmp" > "$smbconf"

  systemctl enable --now smbd nmbd >/dev/null 2>&1 || true
  systemctl restart smbd nmbd || die "Samba konnte nach Einrichtung von wartezimmer-GDT nicht neu gestartet werden."
  ok "Share wartezimmer-GDT nutzt dieselbe Zugriffsregel wie der bestehende GDT-Share"
}

strip_samba_formulare_share() {
  local src="$1"
  local dst="$2"

  awk '
    /^# --- fragebogenpi FORMULARE SHARE BEGIN ---$/ { skip_block=1; next }
    /^# --- fragebogenpi FORMULARE SHARE END ---$/ { skip_block=0; next }
    skip_block == 1 { next }
    /^\[[^]]+\][[:space:]]*$/ {
      section=$0
      gsub(/^\[/, "", section)
      gsub(/\][[:space:]]*$/, "", section)
      skip_section=(tolower(section) == "formulare") ? 1 : 0
      if (skip_section == 1) next
    }
    skip_section != 1 { print }
  ' "$src" > "$dst"
}

write_samba_formulare_block() {
  cat <<EOF

# --- fragebogenpi FORMULARE SHARE BEGIN ---
[formulare]
   path = ${SHARE_FORMULARE}
   browseable = yes
   read only = no
   guest ok = no
   valid users = ${ADMIN_USER}
   force user = www-data
   force group = www-data
# --- fragebogenpi FORMULARE SHARE END ---
EOF
}

setup_samba_tablet_only() {
  step "Samba-Share formulare ergänzen / aktualisieren"

  local smbconf="/etc/samba/smb.conf"
  [[ -f "$smbconf" ]] || die "Samba-Konfiguration fehlt: ${smbconf}. Bitte zuerst eine bestehende Installation vollständig einrichten."

  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"; trap - RETURN' RETURN

  strip_samba_formulare_share "$smbconf" "$tmp"
  write_samba_formulare_block >> "$tmp"

  testparm -s "$tmp" >/dev/null || die "Erzeugte Samba-Konfiguration ist ungültig."
  backup_file "$smbconf"
  cat "$tmp" > "$smbconf"

  systemctl enable --now smbd nmbd >/dev/null 2>&1 || true
  systemctl restart smbd nmbd || die "Samba konnte nach Einrichtung des Formular-Shares nicht neu gestartet werden."
  ok "Share formulare ergänzt; bestehende Shares und globale Einstellungen bleiben erhalten"
}

configure_nm_unmanage_wlan0() {
  if command -v nmcli >/dev/null 2>&1 && systemctl is-active NetworkManager >/dev/null 2>&1; then
    log "NetworkManager erkannt – setze ${AP_INTERFACE} auf unmanaged (nur AP)..."
    mkdir -p /etc/NetworkManager/conf.d
    local nmconf="/etc/NetworkManager/conf.d/99-fragebogenpi-unmanage-${AP_INTERFACE}.conf"
    backup_file "$nmconf"
    cat > "$nmconf" <<EOF
[keyfile]
unmanaged-devices=interface-name:${AP_INTERFACE}
EOF
    systemctl reload NetworkManager || systemctl restart NetworkManager
    command -v udevadm >/dev/null 2>&1 && udevadm settle || true
    sleep 1
  fi
}

install_ap_ip_helper() {
  mkdir -p "$(dirname "$AP_IP_HELPER")"
  backup_file "$AP_IP_HELPER"

  cat > "$AP_IP_HELPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail

AP_INTERFACE="${AP_INTERFACE}"
AP_IP="${AP_IP}"

echo "[fragebogenpi-ap-ip] start: set \${AP_INTERFACE} -> \${AP_IP}/24"

if command -v rfkill >/dev/null 2>&1; then
  rfkill unblock wifi || true
fi

for i in {1..20}; do
  if [[ -d "/sys/class/net/\${AP_INTERFACE}" ]]; then
    break
  fi
  sleep 0.2
done

if [[ ! -d "/sys/class/net/\${AP_INTERFACE}" ]]; then
  echo "[fragebogenpi-ap-ip][ERROR] Interface \${AP_INTERFACE} existiert nicht."
  exit 1
fi

/usr/sbin/ip link set dev "\${AP_INTERFACE}" up
/usr/sbin/ip -4 addr flush dev "\${AP_INTERFACE}" || true
/usr/sbin/ip addr add "\${AP_IP}/24" dev "\${AP_INTERFACE}"

GOT_IP="\$(/usr/sbin/ip -4 -o addr show dev "\${AP_INTERFACE}" | awk '{print \$4}' | cut -d/ -f1 | head -n1 || true)"
if [[ "\${GOT_IP:-}" != "\${AP_IP}" ]]; then
  echo "[fragebogenpi-ap-ip][ERROR] IP setzen fehlgeschlagen: got '\${GOT_IP:-<leer>}' expected '\${AP_IP}'"
  /usr/sbin/ip -4 -br addr show dev "\${AP_INTERFACE}" || true
  exit 1
fi

echo "[fragebogenpi-ap-ip] ok: \${AP_INTERFACE} = \${AP_IP}/24"
EOF

  chmod 0755 "$AP_IP_HELPER"
}

install_ap_ip_service() {
  install_ap_ip_helper

  backup_file "$AP_IP_SERVICE"
  cat > "$AP_IP_SERVICE" <<EOF
[Unit]
Description=fragebogenpi: set static AP IP on ${AP_INTERFACE}
After=NetworkManager.service systemd-udev-settle.service
Wants=systemd-udev-settle.service
Before=hostapd.service dnsmasq.service

[Service]
Type=oneshot
ExecStart=${AP_IP_HELPER}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now fragebogenpi-ap-ip.service || true
  systemctl restart fragebogenpi-ap-ip.service || print_service_debug_and_die "fragebogenpi-ap-ip.service"
}

configure_ap_ip() {
  step "WLAN-AP IP auf wlan0 setzen (10.23.0.1/24)"
  configure_nm_unmanage_wlan0

  if systemd_unit_exists "dhcpcd.service"; then
    log "dhcpcd gefunden – konfiguriere /etc/dhcpcd.conf..."
    local dhcpcd="/etc/dhcpcd.conf"
    backup_file "$dhcpcd"
    sed -i '/^# --- fragebogenpi BEGIN ---$/,/^# --- fragebogenpi END ---$/d' "$dhcpcd" || true
    cat >> "$dhcpcd" <<EOF

# --- fragebogenpi BEGIN ---
interface ${AP_INTERFACE}
  static ip_address=${AP_IP}/24
  nohook wpa_supplicant
# --- fragebogenpi END ---
EOF
    systemctl restart dhcpcd || true
  else
    log "dhcpcd nicht vorhanden – nutze systemd oneshot (iproute2) für persistente AP-IP."
    install_ap_ip_service
  fi

  ip link set dev "${AP_INTERFACE}" up || true
  ip addr add "${AP_IP}/24" dev "${AP_INTERFACE}" 2>/dev/null || true

  local got_ip
  got_ip="$(get_iface_ipv4 "${AP_INTERFACE}")"
  [[ "${got_ip:-}" == "$AP_IP" ]] || die "AP-IP konnte nicht gesetzt werden; wlan0 hat '${got_ip:-<leer>}' statt '${AP_IP}'."

  ok "AP-IP gesetzt (${AP_INTERFACE} = ${AP_IP})"
}

setup_ap_hostapd_dnsmasq() {
  step "WLAN Access Point (hostapd) + DHCP (dnsmasq) konfigurieren"
  local wifi_pw="$1"

  log "Konfiguriere WLAN-Access-Point '${AP_SSID}' auf ${AP_INTERFACE}..."

  local got_ip
  got_ip="$(get_iface_ipv4 "${AP_INTERFACE}")"
  [[ "${got_ip:-}" == "$AP_IP" ]] || die "AP-IP fehlt auf ${AP_INTERFACE}."

  local hostapd_conf="/etc/hostapd/hostapd.conf"
  backup_file "$hostapd_conf"
  cat > "$hostapd_conf" <<EOF
interface=${AP_INTERFACE}
driver=nl80211
country_code=${WIFI_COUNTRY}
ieee80211d=1
ieee80211n=1

ssid=${AP_SSID}
hw_mode=g
channel=6
wmm_enabled=1
auth_algs=1
ignore_broadcast_ssid=0

wpa=2
wpa_passphrase=${wifi_pw}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

  local hostapd_default="/etc/default/hostapd"
  backup_file "$hostapd_default"
  sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' "$hostapd_default" || true

  local dnsmasq_conf="/etc/dnsmasq.d/fragebogenpi.conf"
  backup_file "$dnsmasq_conf"

  local dns_enabled="yes"
  if port_in_use 53; then
    dns_enabled="no"
    warn "Port 53 (DNS) ist belegt. dnsmasq wird DHCP-only gestartet."
  fi

  if [[ "$dns_enabled" == "yes" ]]; then
    cat > "$dnsmasq_conf" <<EOF
interface=${AP_INTERFACE}
bind-interfaces
listen-address=${AP_IP}
dhcp-range=${AP_DHCP_START},${AP_DHCP_END},${AP_NETMASK},12h
address=/#/${AP_IP}
EOF
  else
    cat > "$dnsmasq_conf" <<EOF
interface=${AP_INTERFACE}
bind-interfaces
listen-address=${AP_IP}
port=0
dhcp-range=${AP_DHCP_START},${AP_DHCP_END},${AP_NETMASK},12h
EOF
  fi

  systemctl unmask hostapd >/dev/null 2>&1 || true
  systemctl enable --now hostapd || true
  systemctl restart hostapd || print_service_debug_and_die "hostapd.service"

  systemctl enable --now dnsmasq || true
  systemctl restart dnsmasq || print_service_debug_and_die "dnsmasq.service"

  ok "AP/DHCP aktiv"
}

ensure_ssl_cert_if_requested() {
  local mode="$1"

  if [[ "$mode" == "http" ]]; then
    return 0
  fi

  log "HTTPS gewählt. Erzeuge self-signed Zertifikat für WLAN-Apache (gültig bis 2050)..."

  mkdir -p "$SSL_DIR"
  chmod 700 "$SSL_DIR"

  local end_date="2050-01-01"
  local now_epoch end_epoch days
  now_epoch="$(date +%s)"
  end_epoch="$(date -d "${end_date}" +%s)"
  days="$(( (end_epoch - now_epoch) / 86400 ))"

  openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
    -keyout "$SSL_KEY" -out "$SSL_CRT" \
    -days "$days" \
    -subj "/C=DE/ST=DE/L=DE/O=fragebogenpi/OU=fragebogenpi/CN=${HOSTNAME_FQDN}.local"

  chmod 600 "$SSL_KEY"
  chmod 644 "$SSL_CRT"
}

install_apache_lan_bind_helper() {
  mkdir -p "$(dirname "$APACHE_LAN_BIND_HELPER")"
  backup_file "$APACHE_LAN_BIND_HELPER"

  cat > "$APACHE_LAN_BIND_HELPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail

LAN_INTERFACE="${LAN_INTERFACE}"
AP_IP="${AP_IP}"
PORTS_CONF="/etc/apache2/ports.conf"

find_lan_ip() {
  /usr/sbin/ip -4 -o addr show dev "\${LAN_INTERFACE}" scope global 2>/dev/null \\
    | awk '{print \$4}' \\
    | cut -d/ -f1 \\
    | head -n1
}

lan_ip=""
for _ in {1..30}; do
  lan_ip="\$(find_lan_ip || true)"
  [[ -n "\${lan_ip}" ]] && break
  sleep 1
done

if [[ -z "\${lan_ip}" ]]; then
  echo "[fragebogenpi-apache-lan-bind][WARN] Keine LAN-IP auf \${LAN_INTERFACE}; apache2 wird nur lokal gebunden." >&2
  lan_ip="127.0.0.1"
fi

mkdir -p "\$(dirname "\${PORTS_CONF}")"
touch "\${PORTS_CONF}"

tmp="\$(mktemp)"
awk -v ap_ip="\${AP_IP}" '
  /^# --- fragebogenpi LAN APACHE LISTEN BEGIN ---$/ { skip=1; next }
  /^# --- fragebogenpi LAN APACHE LISTEN END ---$/ { skip=0; next }
  skip == 1 { next }
  /^[[:space:]]*Listen[[:space:]]+/ {
    target=\$2
    if (target == "80" || target == "443" ||
        target == "*:80" || target == "*:443" ||
        target == "0.0.0.0:80" || target == "0.0.0.0:443" ||
        target == "[::]:80" || target == "[::]:443" ||
        target == ap_ip ":80" || target == ap_ip ":443") {
      print "# fragebogenpi disabled generic/AP Listen: " \$0
      next
    }
  }
  { print }
' "\${PORTS_CONF}" > "\${tmp}"

cat >> "\${tmp}" <<BLOCK

# --- fragebogenpi LAN APACHE LISTEN BEGIN ---
Listen \${lan_ip}:80
<IfModule ssl_module>
Listen \${lan_ip}:443
</IfModule>
<IfModule mod_gnutls.c>
Listen \${lan_ip}:443
</IfModule>
# --- fragebogenpi LAN APACHE LISTEN END ---
BLOCK

cat "\${tmp}" > "\${PORTS_CONF}"
rm -f "\${tmp}"
EOF

  chmod 0755 "$APACHE_LAN_BIND_HELPER"
}

configure_apache_lan_instance() {
  local mode="$1"

  install_apache_lan_bind_helper

  backup_file "$APACHE_LAN_BIND_SERVICE"
  cat > "$APACHE_LAN_BIND_SERVICE" <<EOF
[Unit]
Description=fragebogenpi: bind default Apache to LAN only
After=network-online.target
Wants=network-online.target
Before=apache2.service fragebogenpi-apache-wlan.service

[Service]
Type=oneshot
ExecStart=${APACHE_LAN_BIND_HELPER}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  mkdir -p "$APACHE_LAN_DROPIN_DIR"
  backup_file "$APACHE_LAN_DROPIN"
  cat > "$APACHE_LAN_DROPIN" <<EOF
[Unit]
Requires=fragebogenpi-apache-lan-bind.service
After=fragebogenpi-apache-lan-bind.service
EOF

  a2enmod rewrite setenvif >/dev/null || true
  if [[ "$mode" == "https" ]]; then
    a2enmod ssl >/dev/null || true
  fi

  systemctl daemon-reload
  systemctl enable --now fragebogenpi-apache-lan-bind.service >/dev/null 2>&1 || true
  systemctl restart fragebogenpi-apache-lan-bind.service || print_service_debug_and_die "fragebogenpi-apache-lan-bind.service"
  systemctl restart apache2 || print_service_debug_and_die "apache2.service"
}

write_apache_wlan_config() {
  local mode="$1"

  mkdir -p "$APACHE_WLAN_DIR" "$APACHE_WLAN_LOG_DIR"
  backup_file "$APACHE_WLAN_CONF"

  cat > "$APACHE_WLAN_CONF" <<EOF
ServerRoot "${APACHE_WLAN_DIR}"
PidFile ${APACHE_WLAN_RUN_DIR}/apache2.pid
DefaultRuntimeDir ${APACHE_WLAN_RUN_DIR}
Mutex file:${APACHE_WLAN_RUN_DIR} default

User www-data
Group www-data
ServerName ${HOSTNAME_FQDN}.local

Listen ${AP_IP}:80
EOF

  if [[ "$mode" == "https" ]]; then
    cat >> "$APACHE_WLAN_CONF" <<EOF
Listen ${AP_IP}:443
EOF
  fi

  cat >> "$APACHE_WLAN_CONF" <<EOF

TypesConfig /etc/mime.types
DirectoryIndex index.php index.html

ErrorLog ${APACHE_WLAN_LOG_DIR}/fragebogenpi-wlan-error.log
LogLevel warn

IncludeOptional /etc/apache2/mods-enabled/*.load
IncludeOptional /etc/apache2/mods-enabled/*.conf

# wartezimmer-server.php nicht im Apache-Zugriffslog protokollieren
SetEnvIf Request_URI "^/wartezimmer-server\.php$" wartezimmer_no_log

<Directory />
    AllowOverride None
    Require all denied
</Directory>

<Directory "${WEBROOT_WLAN}">
    Options FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

<VirtualHost ${AP_IP}:80>
    ServerName ${HOSTNAME_FQDN}.local
    DocumentRoot "${WEBROOT_WLAN}"
    ErrorLog ${APACHE_WLAN_LOG_DIR}/fragebogenpi-wlan-http-error.log
    CustomLog ${APACHE_WLAN_LOG_DIR}/fragebogenpi-wlan-http-access.log combined env=!wartezimmer_no_log
</VirtualHost>
EOF

  if [[ "$mode" == "https" ]]; then
    cat >> "$APACHE_WLAN_CONF" <<EOF

<VirtualHost ${AP_IP}:443>
    ServerName ${HOSTNAME_FQDN}.local
    DocumentRoot "${WEBROOT_WLAN}"
    SSLEngine on
    SSLCertificateFile ${SSL_CRT}
    SSLCertificateKeyFile ${SSL_KEY}
    ErrorLog ${APACHE_WLAN_LOG_DIR}/fragebogenpi-wlan-https-error.log
    CustomLog ${APACHE_WLAN_LOG_DIR}/fragebogenpi-wlan-https-access.log combined env=!wartezimmer_no_log
</VirtualHost>
EOF
  fi
}

install_apache_wlan_service() {
  backup_file "$APACHE_WLAN_SERVICE"
  cat > "$APACHE_WLAN_SERVICE" <<EOF
[Unit]
Description=fragebogenpi: isolated Apache instance for WLAN
After=network-online.target fragebogenpi-ap-ip.service fragebogenpi-apache-lan-bind.service
Wants=network-online.target
Requires=fragebogenpi-apache-lan-bind.service

[Service]
Type=simple
RuntimeDirectory=fragebogenpi-apache-wlan
Environment=APACHE_RUN_DIR=${APACHE_WLAN_RUN_DIR}
Environment=APACHE_PID_FILE=${APACHE_WLAN_RUN_DIR}/apache2.pid
Environment=APACHE_LOCK_DIR=${APACHE_WLAN_RUN_DIR}
Environment=APACHE_LOG_DIR=${APACHE_WLAN_LOG_DIR}
ExecStartPre=/bin/sh -c 'for _ in \$(seq 1 30); do /usr/sbin/ip -4 addr show dev ${AP_INTERFACE} | /bin/grep -q "${AP_IP}/" && exit 0; sleep 1; done; exit 1'
ExecStart=/usr/sbin/apache2 -f ${APACHE_WLAN_CONF} -DFOREGROUND
ExecReload=/usr/sbin/apache2 -f ${APACHE_WLAN_CONF} -k graceful
KillSignal=SIGWINCH
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
}

setup_apache_instances() {
  step "Apache trennen: LAN-Instanz und isolierte WLAN-Instanz"
  local mode="$1"

  ensure_ssl_cert_if_requested "$mode"
  configure_apache_lan_instance "$mode"
  write_apache_wlan_config "$mode"
  install_apache_wlan_service

  systemctl daemon-reload
  systemctl enable --now fragebogenpi-apache-wlan.service >/dev/null 2>&1 || true
  systemctl restart fragebogenpi-apache-wlan.service || print_service_debug_and_die "fragebogenpi-apache-wlan.service"

  if [[ "$mode" == "https" ]]; then
    ok "Apache getrennt: LAN nur auf ${LAN_INTERFACE}, WLAN HTTP/HTTPS nur auf ${AP_IP} mit ${WEBROOT_WLAN}"
  else
    ok "Apache getrennt: LAN nur auf ${LAN_INTERFACE}, WLAN HTTP nur auf ${AP_IP} mit ${WEBROOT_WLAN}"
  fi
}

configure_waiting_room_no_access_log() {
  [[ -f "$APACHE_WLAN_CONF" ]] || die "WLAN-Apache-Konfiguration fehlt: ${APACHE_WLAN_CONF}"

  a2enmod setenvif >/dev/null 2>&1 || true

  if ! grep -q '^# wartezimmer-server.php nicht im Apache-Zugriffslog protokollieren$' "$APACHE_WLAN_CONF"; then
    sed -i '/^IncludeOptional \/etc\/apache2\/mods-enabled\/\*\.conf$/a\
\
# wartezimmer-server.php nicht im Apache-Zugriffslog protokollieren\
SetEnvIf Request_URI "^/wartezimmer-server\\.php$" wartezimmer_no_log' "$APACHE_WLAN_CONF"
  fi

  sed -i -E '/CustomLog .*fragebogenpi-wlan-(http|https)-access\.log combined$/s/$/ env=!wartezimmer_no_log/' "$APACHE_WLAN_CONF"

  APACHE_RUN_DIR="$APACHE_WLAN_RUN_DIR" \
  APACHE_PID_FILE="${APACHE_WLAN_RUN_DIR}/apache2.pid" \
  APACHE_LOCK_DIR="$APACHE_WLAN_RUN_DIR" \
  APACHE_LOG_DIR="$APACHE_WLAN_LOG_DIR" \
    /usr/sbin/apache2 -t -f "$APACHE_WLAN_CONF" >/dev/null || \
    die "WLAN-Apache-Konfiguration ist nach der Wartezimmer-Ergänzung ungültig."
}

ensure_apache_lan_bind_service_active() {
  [[ -f "$APACHE_LAN_BIND_SERVICE" ]] || \
    die "Apache-LAN-Bind-Dienst fehlt: ${APACHE_LAN_BIND_SERVICE}"

  if ! grep -q '^RemainAfterExit=yes$' "$APACHE_LAN_BIND_SERVICE"; then
    backup_file "$APACHE_LAN_BIND_SERVICE"
    sed -i '/^Type=oneshot$/aRemainAfterExit=yes' "$APACHE_LAN_BIND_SERVICE"
  fi

  systemctl daemon-reload
  systemctl reset-failed fragebogenpi-apache-lan-bind.service >/dev/null 2>&1 || true
  systemctl start fragebogenpi-apache-lan-bind.service || \
    print_service_debug_and_die "fragebogenpi-apache-lan-bind.service"
}

write_waiting_room_server_config() {
  local first_shorten_php="false"
  local first_dot_php="false"
  local last_shorten_php="false"
  local last_dot_php="false"

  [[ "$WAITING_SHORTEN_FIRST" == "yes" ]] && first_shorten_php="true"
  [[ "$WAITING_FIRST_DOT" == "yes" ]] && first_dot_php="true"
  [[ "$WAITING_SHORTEN_LAST" == "yes" ]] && last_shorten_php="true"
  [[ "$WAITING_LAST_DOT" == "yes" ]] && last_dot_php="true"

  mkdir -p "$(dirname "$WAITING_ROOM_CONFIG")"
  cat > "$WAITING_ROOM_CONFIG" <<EOF
<?php
return [
    'share_dir' => '${SHARE_WAITING_ROOM}',
    'lock_file' => '${WAITING_ROOM_LOCK}',
    'shorten_first_name' => ${first_shorten_php},
    'first_name_letters' => ${WAITING_FIRST_LETTERS},
    'first_name_dot' => ${first_dot_php},
    'shorten_last_name' => ${last_shorten_php},
    'last_name_letters' => ${WAITING_LAST_LETTERS},
    'last_name_dot' => ${last_dot_php},
];
EOF

  chown root:www-data "$WAITING_ROOM_CONFIG"
  chmod 0640 "$WAITING_ROOM_CONFIG"
}

install_waiting_room_server_file() {
  ensure_command curl curl

  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"; trap - RETURN' RETURN

  curl -fsSL "$WAITING_ROOM_SERVER_URL" -o "$tmp" || die "Download fehlgeschlagen: ${WAITING_ROOM_SERVER_URL}"
  php -l "$tmp" >/dev/null || die "Heruntergeladene wartezimmer-server.php enthält einen PHP-Syntaxfehler."

  mkdir -p "$(dirname "$WAITING_ROOM_SERVER")"
  cp "$tmp" "$WAITING_ROOM_SERVER"
  chown www-data:www-data "$WAITING_ROOM_SERVER"
  chmod 0644 "$WAITING_ROOM_SERVER"
}

setup_waiting_room_interface() {
  step "Wartezimmer-Schnittstelle einrichten"

  mkdir -p "$SHARE_WAITING_ROOM"
  chown www-data:www-data "$SHARE_WAITING_ROOM"
  chmod 2775 "$SHARE_WAITING_ROOM"
  setfacl -R -m u:www-data:rwx "$SHARE_WAITING_ROOM" || true
  setfacl -R -d -m u:www-data:rwx "$SHARE_WAITING_ROOM" || true

  touch "$WAITING_ROOM_LOCK"
  chown www-data:www-data "$WAITING_ROOM_LOCK"
  chmod 0660 "$WAITING_ROOM_LOCK"

  write_waiting_room_server_config
  install_waiting_room_server_file
  configure_waiting_room_no_access_log
  ensure_apache_lan_bind_service_active

  systemctl reset-failed fragebogenpi-apache-wlan.service >/dev/null 2>&1 || true
  if systemctl is-active --quiet fragebogenpi-apache-wlan.service; then
    systemctl reload fragebogenpi-apache-wlan.service || \
      print_service_debug_and_die "fragebogenpi-apache-wlan.service"
  else
    systemctl start fragebogenpi-apache-wlan.service || \
      print_service_debug_and_die "fragebogenpi-apache-wlan.service"
  fi
  ok "Wartezimmer-Schnittstelle aktiv: http://${AP_IP}/wartezimmer-server.php"
}

setup_firewall_nftables_wlan_only() {
  step "Firewall: nur WLAN beschränken, LAN unberührt lassen (kein Routing)"
  local web_mode="$1"

  local nftconf="/etc/nftables.conf"
  backup_file "$nftconf"

  local web_allow_rule='    iif "'${AP_INTERFACE}'" ip daddr '${AP_IP}' tcp dport 80 accept'
  if [[ "$web_mode" == "https" ]]; then
    web_allow_rule='    iif "'${AP_INTERFACE}'" ip daddr '${AP_IP}' tcp dport { 80, 443 } accept'
  fi

  cat > "$nftconf" <<EOF
#!/usr/sbin/nft -f

table inet fragebogenpi {
  chain input {
    type filter hook input priority 0;
    policy accept;

    iif "${AP_INTERFACE}" ct state established,related accept
    iif "${AP_INTERFACE}" tcp dport 22 drop
    iif "${AP_INTERFACE}" udp dport { 67, 68 } accept
    iif "${AP_INTERFACE}" udp dport 53 accept
${web_allow_rule}
    iif "${AP_INTERFACE}" drop
  }

  chain forward {
    type filter hook forward priority 0;
    policy accept;

    # Kein Routing zwischen WLAN und anderen Interfaces
    iif "${AP_INTERFACE}" drop
    oif "${AP_INTERFACE}" drop
  }

  chain output {
    type filter hook output priority 0;
    policy accept;
  }
}
EOF

  systemctl enable --now nftables
  systemctl restart nftables

  cat > /etc/sysctl.d/99-fragebogenpi.conf <<EOF
net.ipv4.ip_forward=0
net.ipv6.conf.all.forwarding=0
EOF
  sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.all.forwarding=0 >/dev/null 2>&1 || true

  ok "WLAN restriktiv (inkl. SSH block), LAN frei, Routing aus"
}

ensure_sshd_normal_listen() {
  step "SSH Strategie: sshd 'wie normal' auf allen Interfaces (ListenAddress entfernen)"
  local sshd_conf="/etc/ssh/sshd_config"
  if [[ ! -f "$sshd_conf" ]]; then
    warn "sshd_config nicht gefunden – überspringe."
    return 0
  fi
  backup_file "$sshd_conf"
  sed -i '/^\s*ListenAddress\s\+/d' "$sshd_conf"
  sed -i '/^# --- fragebogenpi: SSH nur im LAN ---$/d' "$sshd_conf" || true
  sed -i '/^# --- \/fragebogenpi ---$/d' "$sshd_conf" || true
  systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
  ok "sshd lauscht wieder standardmäßig"
}

configure_php_settings() {
  step "PHP Optionen setzen (Upload/Timeouts) + Apache reload"

  local php_ver
  php_ver="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"

  local apache_conf_dir="/etc/php/${php_ver}/apache2/conf.d"
  local cli_conf_dir="/etc/php/${php_ver}/cli/conf.d"
  local ini_name="99-fragebogenpi.ini"

  mkdir -p "$apache_conf_dir" "$cli_conf_dir"

  cat > "${apache_conf_dir}/${ini_name}" <<EOF
; fragebogenpi custom PHP settings
upload_max_filesize = ${PHP_UPLOAD_MAX}
post_max_size = ${PHP_POST_MAX}
max_file_uploads = ${PHP_MAX_UPLOADS}
max_execution_time = ${PHP_MAX_EXEC}
max_input_time = ${PHP_MAX_INPUT}
EOF

  cp -a "${apache_conf_dir}/${ini_name}" "${cli_conf_dir}/${ini_name}"
  systemctl reload apache2
  systemctl reload fragebogenpi-apache-wlan.service >/dev/null 2>&1 || \
    systemctl restart fragebogenpi-apache-wlan.service >/dev/null 2>&1 || true

  ok "PHP Optionen gesetzt (Apache LAN + Apache WLAN + CLI) für PHP ${php_ver}"
}

enable_auto_updates() {
  step "Auto-Update aktivieren (unattended-upgrades als Paket)"

  local auto_conf="/etc/apt/apt.conf.d/20auto-upgrades"
  backup_file "$auto_conf"

  cat > "$auto_conf" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

  systemctl enable unattended-upgrades >/dev/null 2>&1 || true
  systemctl start unattended-upgrades >/dev/null 2>&1 || true

  systemctl enable apt-daily.timer >/dev/null 2>&1 || true
  systemctl enable apt-daily-upgrade.timer >/dev/null 2>&1 || true

  ok "Auto-Updates aktiviert (APT periodic + unattended-upgrades)"
}

download_tablet_php_only() {
  step "Tablet-Programm aktualisieren"

  ensure_command curl curl
  local base_url tmp dst
  base_url="$(echo "$BOOTSTRAP_URL" | sed 's#^\(.*\)/[^/]*$#\1#')"
  dst="${WEBROOT}/tablet.php"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"; trap - RETURN' RETURN

  curl -fsSL "${base_url}/tablet.php" -o "$tmp" || die "Download fehlgeschlagen: tablet.php"
  mkdir -p "$WEBROOT"
  backup_file "$dst"
  mv "$tmp" "$dst"
  chown www-data:www-data "$dst" || true
  chmod 0644 "$dst"
  ok "tablet.php aktualisiert"
}

install_tablet_endpoints() {
  step "Tablet-Endpunkte und Formularvorlage bereitstellen"

  [[ -f "${WEBROOT}/tablet.php" ]] || die "tablet.php fehlt im WLAN-Webroot."
  [[ -f "${WEBROOT}/anamnesebogen.yaml" ]] || die "anamnesebogen.yaml fehlt im WLAN-Webroot."
  mkdir -p "$SHARE_FORMULARE"

  if [[ ! -f "${SHARE_FORMULARE}/anam.yaml" ]]; then
    cp -a "${WEBROOT}/anamnesebogen.yaml" "${SHARE_FORMULARE}/anam.yaml"
  else
    log "Bestehende Formularvorlage anam.yaml bleibt erhalten."
  fi
  chown www-data:www-data "${SHARE_FORMULARE}/anam.yaml" || true
  chmod 0664 "${SHARE_FORMULARE}/anam.yaml"

  chown www-data:www-data "${WEBROOT}/tablet.php" || true
  chmod 0644 "${WEBROOT}/tablet.php"

  local tablet_id endpoint
  for ((tablet_id=1; tablet_id<=TABLET_COUNT; tablet_id++)); do
    if (( TABLET_COUNT == 1 )); then
      continue
    fi
    endpoint="${WEBROOT}/tablet${tablet_id}.php"
    backup_file "$endpoint"
    cp -a "${WEBROOT}/tablet.php" "$endpoint"
    chown www-data:www-data "$endpoint" || true
    chmod 0644 "$endpoint"
  done

  for ((tablet_id=1; tablet_id<=9; tablet_id++)); do
    if (( tablet_id <= TABLET_COUNT )); then
      continue
    fi
    endpoint="${WEBROOT}/tablet${tablet_id}.php"
    if [[ -f "$endpoint" ]] && cmp -s "$endpoint" "${WEBROOT}/tablet.php"; then
      backup_file "$endpoint"
      rm -f "$endpoint"
    fi
  done

  save_tablet_count
  ok "Tablet-Betrieb eingerichtet (${TABLET_COUNT} Tablet(s)); anamnesebogen.yaml wurde als anam.yaml bereitgestellt"
}

download_bootstrap_files_to_webroot() {
  step "WLAN-Webroot Bootstrap: Dateiliste laden und Dateien herunterladen"

  ensure_command curl curl

  local base_url
  base_url="$(echo "$BOOTSTRAP_URL" | sed 's#^\(.*\)/[^/]*$#\1#')"

  log "Lade Bootstrap-Liste:"
  log "  ${BOOTSTRAP_URL}"

  local tmp_list
  tmp_list="$(mktemp)"
  trap 'rm -f "$tmp_list"; trap - RETURN' RETURN

  curl -fsSL "$BOOTSTRAP_URL" -o "$tmp_list" || die "Download fehlgeschlagen: bootstrap"

  local count_skipped=0
  local count_ok=0

  while IFS= read -r raw || [[ -n "$raw" ]]; do
    local line
    line="$(echo "$raw" | sed -e 's/\r$//' -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"

    if [[ -z "$line" ]] || [[ "$line" == \#* ]]; then
      count_skipped=$((count_skipped+1))
      continue
    fi

    sanitize_relpath_or_die "$line"

    local url="${base_url}/${line}"
    local dst="${WEBROOT}/${line}"
    local dst_dir
    dst_dir="$(dirname "$dst")"
    mkdir -p "$dst_dir"

    log "Download: ${line}"
    curl -fsSL "$url" -o "$dst" || die "Download fehlgeschlagen: ${url}"

    chown www-data:www-data "$dst" || true
    chmod 0644 "$dst" || true

    count_ok=$((count_ok+1))
  done < "$tmp_list"

  ok "Bootstrap abgeschlossen: ${count_ok} Datei(en) geladen (Kommentare/leer: ${count_skipped})"
}

write_credentials_file_if_requested() {
  local want="$1"
  local web_mode="$2"
  local protect_shares="$3"
  local wifi_pw="$4"
  local samba_pw="$5"
  local admin_pw="$6"
  local lan_ip="$7"
  local lan_mac="$8"
  local ap_mac="$9"

  if [[ "$want" != "yes" ]]; then
    log "Zugangsdaten-Datei: nicht gewünscht – überspringe."
    return 0
  fi

  step "Zugangsdaten-Datei ins PDF-Share schreiben (bitte danach löschen!)"

  mkdir -p "$SHARE_PDF"

  local old_umask
  old_umask="$(umask)"
  umask 077

  {
    echo "############################################################"
    echo "# zugangsdaten_fragebogenpi_bitte_loeschen.txt"
    echo "# WICHTIG: Diese Datei enthält Passwörter -> nach Übernahme löschen!"
    echo "############################################################"
    echo
    echo "Projekt: fragebogenpi"
    echo "Version: ${VERSION}"
    echo "Hostname: ${HOSTNAME_FQDN}"
    echo
    echo "== Netzwerk / Erreichbarkeit =="
    echo "LAN IP (aktuell): ${lan_ip:-<unbekannt>}"
    echo "LAN MAC (eth0):   ${lan_mac:-<unbekannt>}"
    echo "WLAN MAC (wlan0): ${ap_mac:-<unbekannt>}"
    echo
    echo "HTTP/HTTPS:"
    echo "  - http(s)://${HOSTNAME_FQDN}/        (nur wenn Router/DNS Name auflöst)"
    echo "  - http(s)://${HOSTNAME_FQDN}.local/  (mDNS/Bonjour)"
    echo "  - http(s)://<IP-Adresse>/"
    echo
    echo "== WLAN (isoliert) =="
    echo "SSID: ${AP_SSID}"
    echo "WLAN Passwort: ${wifi_pw}"
    echo "WLAN IP (Pi): ${AP_IP}"
    echo "Webserver (WLAN): http://${AP_IP}/"
    if [[ "$web_mode" == "https" ]]; then
      echo "Webserver (WLAN): https://${AP_IP}/ (self-signed)"
    fi
    echo "WLAN-Webroot: ${WEBROOT_WLAN}"
    echo "LAN-Webroot:  ${WEBROOT_LAN}"
    echo "Apache: WLAN läuft isoliert über fragebogenpi-apache-wlan.service; apache2 bleibt LAN-gebunden."
    echo
    echo "== Samba (nur LAN) =="
    echo "\\\\<LAN-IP>\\GDT      -> ${SHARE_GDT}"
    echo "\\\\<LAN-IP>\\PDF      -> ${SHARE_PDF}"
    echo "\\\\<LAN-IP>\\formulare -> ${SHARE_FORMULARE}"
    echo "\\\\<LAN-IP>\\webroot-wlan  -> ${WEBROOT_WLAN}"
    echo "\\\\<LAN-IP>\\webroot-lan   -> ${WEBROOT_LAN}"
    if [[ "$WAITING_ROOM_ENABLED" == "yes" ]]; then
      echo "\\\\<LAN-IP>\\wartezimmer-GDT -> ${SHARE_WAITING_ROOM}"
      echo "Wartezimmer-Query: http://${AP_IP}/wartezimmer-server.php"
    fi
    echo
    if [[ "$protect_shares" == "yes" ]]; then
      if [[ "$WAITING_ROOM_ENABLED" == "yes" ]]; then
        echo "User (GDT/PDF/wartezimmer-GDT): ${SAMBA_USER}"
      else
        echo "User (GDT/PDF): ${SAMBA_USER}"
      fi
      echo "Passwort:       ${samba_pw}"
    else
      if [[ "$WAITING_ROOM_ENABLED" == "yes" ]]; then
        echo "GDT/PDF/wartezimmer-GDT Zugriff: anonym (guest), schreibbar"
      else
        echo "GDT/PDF Zugriff: anonym (guest), schreibbar"
      fi
    fi
    echo
    echo "Admin (webroot-wlan/webroot-lan/SSH/sudo): ${ADMIN_USER}"
    echo "Admin Passwort (generiert):  ${admin_pw}"
    echo
    if (( ${#EXTRA_USERS_LIST[@]} > 0 )); then
      echo "== Zusätzliche Windows-/Samba-User =="
      local idx=0
      for u in "${EXTRA_USERS_LIST[@]}"; do
        if [[ "${EXTRA_USERS_MODE[$idx]}" == "generated" ]]; then
          echo "- ${u}: Passwort (generiert) = ${EXTRA_USERS_PW[$idx]}"
        else
          echo "- ${u}: Passwort (manuell gesetzt, nicht angezeigt)"
        fi
        idx=$((idx+1))
      done
      echo
    fi
    echo "== Bootstrap =="
    echo "Quelle: ${BOOTSTRAP_URL}"
    echo "Hinweis: Dateien wurden in den isolierten WLAN-Webroot geladen (ggf. Unterverzeichnisse)."
    echo
    echo "== Tablet-/Formularbetrieb =="
    echo "Tablets: ${TABLET_COUNT}"
    echo "Einzelgerät: anam-i.gdt / anam-o.gdt"
    echo "Mehrgerätebetrieb: <tablet-id>-anam-i.gdt / <tablet-id>-anam-o.gdt"
    echo
    echo "== PHP Optionen =="
    echo "upload_max_filesize=${PHP_UPLOAD_MAX}"
    echo "post_max_size=${PHP_POST_MAX}"
    echo "max_file_uploads=${PHP_MAX_UPLOADS}"
    echo "max_execution_time=${PHP_MAX_EXEC}"
    echo "max_input_time=${PHP_MAX_INPUT}"
    echo
    echo "== Auto-Update =="
    echo "unattended-upgrades: aktiv"
    echo
    echo "############################################################"
    echo "# Bitte diese Datei nach dem Notieren/Übernehmen löschen!"
    echo "############################################################"
  } > "$CRED_FILE"

  umask "$old_umask"

  chown www-data:www-data "$CRED_FILE" || true
  chmod 0664 "$CRED_FILE" || true

  ok "Zugangsdaten-Datei geschrieben: ${CRED_FILE}"
}

# -------------------------
# Main
# -------------------------
main() {
  require_root
  banner

  log "Starte Setup 'fragebogenpi' (v${VERSION})..."

  if [[ ! -d /sys/class/net/${AP_INTERFACE} ]]; then
    die "Interface ${AP_INTERFACE} nicht gefunden."
  fi
  if [[ ! -d /sys/class/net/${LAN_INTERFACE} ]]; then
    warn "Interface ${LAN_INTERFACE} nicht gefunden (LAN). Samba/Bindung gilt dann evtl. nicht."
  fi

  local mode="full"
  if [[ -d "${SHARE_BASE}" ]]; then
    mode="$(ask_choice_existing_install)"
  fi

  # ------------------------------------------------------
  # Modus 4: Nur Wartezimmer-Schnittstelle
  # ------------------------------------------------------
  if [[ "$mode" == "waiting" ]]; then
    step "Modus: Nur Wartezimmer-Schnittstelle einrichten / aktualisieren"
    log "Andere Shares, Passwörter, WLAN, Firewall und Bootstrap-Dateien bleiben unverändert."

    install_packages_waiting_room_only
    ask_waiting_room_privacy_config
    setup_waiting_room_interface
    setup_samba_waiting_room_only

    step "Abschluss (Wartezimmer-Schnittstelle)"
    echo
    echo "Samba-Share (nur LAN):"
    echo "  \\\\<LAN-IP-des-Pi>\\wartezimmer-GDT -> ${SHARE_WAITING_ROOM}"
    echo "WLAN-Server:"
    echo "  http://${AP_IP}/wartezimmer-server.php"
    echo
    exit 0
  fi

  # ------------------------------------------------------
  # Modus 5: Nur Tablet-/Formularbetrieb
  # ------------------------------------------------------
  if [[ "$mode" == "tablets" ]]; then
    step "Modus: Nur Tablet-/Formularbetrieb einrichten / aktualisieren"
    log "WLAN, LAN, Hostname, Firewall, Apache-Grundkonfiguration und bestehende Shares bleiben unverändert."

    install_packages_webroot_only
    ask_tablet_count
    setup_formulare_dir_only
    setup_samba_tablet_only
    download_tablet_php_only
    install_tablet_endpoints

    step "Abschluss (Tablet-/Formularbetrieb)"
    echo
    echo "Tablets: ${TABLET_COUNT}"
    if (( TABLET_COUNT == 1 )); then
      echo "Web-App: http(s)://<Pi>/tablet.php"
    else
      local tablet_id
      for ((tablet_id=1; tablet_id<=TABLET_COUNT; tablet_id++)); do
        echo "Web-App Tablet ${tablet_id}: http(s)://<Pi>/tablet${tablet_id}.php"
      done
    fi
    echo "Formular-Share: \\\\<LAN-IP-des-Pi>\\formulare -> ${SHARE_FORMULARE}"
    echo "Eingangs-GDT: anam-i.gdt beziehungsweise 1-anam-i.gdt"
    echo "Bestehende WLAN-/Netzwerk-Konfiguration wurde nicht verändert."
    echo
    exit 0
  fi

  # ------------------------------------------------------
  # Modus 3: Nur User hinzufügen / reparieren
  # ------------------------------------------------------
  if [[ "$mode" == "users" ]]; then
    step "Modus: Nur User hinzufügen / reparieren"
    log "Es werden NUR zusätzliche Windows-/Samba-User angelegt/aktualisiert."
    log "Netzwerk/Samba-Config/Firewall/AP/Webroot/PHP/sonstiges bleibt unverändert."

    install_packages_users_only
    manage_users_interactive "Zusätzliche Windows-/Samba-User (nur User-Modus)"

    step "Abschluss (nur User)"
    echo
    echo "Zusätzliche User wurden angelegt/aktualisiert."
    echo "Hinweis: Eingegebene Passwörter werden nicht ausgegeben."
    if (( ${#EXTRA_USERS_LIST[@]} > 0 )); then
      echo
      echo "Generierte Passwörter:"
      local idx=0
      for u in "${EXTRA_USERS_LIST[@]}"; do
        if [[ "${EXTRA_USERS_MODE[$idx]}" == "generated" ]]; then
          echo "  - ${u}: ${EXTRA_USERS_PW[$idx]}"
        fi
        idx=$((idx+1))
      done
      echo
    fi
    exit 0
  fi

  # ------------------------------------------------------
  # Modus 2: Nur Webroot-Update (Bootstrap-Dateien)
  # ------------------------------------------------------
  if [[ "$mode" == "webroot" ]]; then
    step "Modus: Nur Webroot-Update"
    log "Es werden NUR die Bootstrap-Dateien in den isolierten WLAN-Webroot geladen."
    log "Netzwerk/Samba/Firewall/Passwörter bleiben unverändert."

    install_packages_webroot_only
    setup_webroot_perms
    download_bootstrap_files_to_webroot

    step "Abschluss (Webroot-Update)"
    echo
    echo "Webroot-Update abgeschlossen."
    echo "Quelle (Bootstrap): ${BOOTSTRAP_URL}"
    echo "Ziel (WLAN-Webroot): ${WEBROOT_WLAN}"
    echo "Hinweis: Bestehende Dateien wurden überschrieben."
    echo
    exit 0
  fi

  # ------------------------------------------------------
  # Modus 1: Vollinstallation / Neu-Konfiguration
  # ------------------------------------------------------
  step "Konfiguration abfragen"
  local wifi_pw web_mode protect_shares samba_pw admin_pw save_creds
  ask_hostname_setup
  ask_ap_ssid_setup
  wifi_pw="$(rand_pw)"
  web_mode="$(ask_choice_http_https)"
  ask_tablet_count

  WAITING_ROOM_ENABLED="no"
  if ask_yes_no "Separaten Samba-Share 'wartezimmer-GDT' einrichten?" "n"; then
    WAITING_ROOM_ENABLED="yes"
    ask_waiting_room_privacy_config
  fi

  protect_shares="no"
  samba_pw=""
  local protected_share_names="GDT/PDF"
  if [[ "$WAITING_ROOM_ENABLED" == "yes" ]]; then
    protected_share_names="GDT/PDF/wartezimmer-GDT"
  fi
  if ask_yes_no "Samba-Shares ${protected_share_names} mit Passwort schützen (User '${SAMBA_USER}')?" "y"; then
    protect_shares="yes"
    samba_pw="$(rand_pw)"
  fi

  admin_pw="$(rand_pw)"

  save_creds="no"
  if ask_yes_no "Zugangsdaten zusätzlich als Datei ins PDF-Share schreiben (BITTE danach löschen)?" "n"; then
    save_creds="yes"
  fi

  ok "Eingaben übernommen"

  install_packages_full

  manage_users_interactive "Zusätzliche Windows-/Samba-User (optional)"

  local extra_users_space=""
  if (( ${#EXTRA_USERS_LIST[@]} > 0 )); then
    extra_users_space="${EXTRA_USERS_LIST[*]}"
  fi

  set_hostname
  setup_share_dirs "$WAITING_ROOM_ENABLED"
  setup_webroot_perms

  setup_samba "$protect_shares" "$samba_pw" "$admin_pw" "$extra_users_space" "$WAITING_ROOM_ENABLED"

  configure_nm_unmanage_wlan0
  configure_ap_ip
  setup_ap_hostapd_dnsmasq "$wifi_pw"
  setup_apache_instances "$web_mode"
  if [[ "$WAITING_ROOM_ENABLED" == "yes" ]]; then
    setup_waiting_room_interface
  fi

  setup_firewall_nftables_wlan_only "$web_mode"
  ensure_sshd_normal_listen

  configure_php_settings
  download_bootstrap_files_to_webroot
  install_tablet_endpoints
  enable_auto_updates

  local lan_ip lan_mac ap_mac
  lan_ip="$(get_iface_ipv4 "${LAN_INTERFACE}")"
  lan_mac="$(get_iface_mac "${LAN_INTERFACE}")"
  ap_mac="$(get_iface_mac "${AP_INTERFACE}")"

  write_credentials_file_if_requested \
    "$save_creds" "$web_mode" "$protect_shares" "$wifi_pw" "$samba_pw" "$admin_pw" \
    "$lan_ip" "$lan_mac" "$ap_mac"

  step "Abschlussinformationen"
  log "Fertig."

  echo
  echo "==================== ZUGANGSDATEN ===================="
  echo "Hostname (System):      ${HOSTNAME_FQDN}"
  echo
  echo "Namensauflösung / Erreichbarkeit:"
  echo "  - http(s)://${HOSTNAME_FQDN}/        -> nur wenn Router/DNS Hostnamen auflöst"
  echo "  - http(s)://${HOSTNAME_FQDN}.local/  -> mDNS/Bonjour (empfohlen)"
  echo "  - http(s)://<IP-Adresse>/        -> funktioniert immer"
  echo
  echo "WLAN SSID:        ${AP_SSID}"
  echo "WLAN Passwort:    ${wifi_pw}"
  echo "WLAN IP (Pi):     ${AP_IP}"
  echo "Webserver (WLAN): http://${AP_IP}/"
  if [[ "$web_mode" == "https" ]]; then
    echo "Webserver (WLAN): https://${AP_IP}/  (self-signed Warnung ist normal)"
  fi
  echo "WLAN-Webroot:     ${WEBROOT_WLAN}"
  echo "LAN-Webroot:      ${WEBROOT_LAN}"
  echo "Apache Isolation: WLAN nutzt fragebogenpi-apache-wlan.service; Standard-apache2 ist LAN-gebunden."
  echo
  echo "LAN IP (aktuell): ${lan_ip:-<unbekannt>}"
  echo "LAN MAC (eth0):   ${lan_mac:-<unbekannt>}"
  echo "WLAN MAC (wlan0): ${ap_mac:-<unbekannt>}"
  echo
  echo "Samba Shares (nur LAN/eth0, nicht WLAN):"
  echo "  \\\\<LAN-IP-des-Pi>\\GDT      -> ${SHARE_GDT}"
  echo "  \\\\<LAN-IP-des-Pi>\\PDF      -> ${SHARE_PDF}"
  echo "  \\\\<LAN-IP-des-Pi>\\formulare -> ${SHARE_FORMULARE}"
  echo "  \\\\<LAN-IP-des-Pi>\\webroot-wlan  -> ${WEBROOT_WLAN}"
  echo "  \\\\<LAN-IP-des-Pi>\\webroot-lan   -> ${WEBROOT_LAN}"
  if [[ "$WAITING_ROOM_ENABLED" == "yes" ]]; then
    echo "  \\\\<LAN-IP-des-Pi>\\wartezimmer-GDT -> ${SHARE_WAITING_ROOM}"
    echo "  Wartezimmer-Query: http://${AP_IP}/wartezimmer-server.php"
  fi
  echo
  if [[ "$protect_shares" == "yes" ]]; then
    if [[ "$WAITING_ROOM_ENABLED" == "yes" ]]; then
      echo "Samba User (GDT/PDF/wartezimmer-GDT): ${SAMBA_USER}"
    else
      echo "Samba User (GDT/PDF):   ${SAMBA_USER}"
    fi
    echo "Samba Passwort:         ${samba_pw}"
    if [[ -n "${extra_users_space// }" ]]; then
      echo "Weitere gültige User (GDT/PDF): ${extra_users_space}"
    fi
  else
    if [[ "$WAITING_ROOM_ENABLED" == "yes" ]]; then
      echo "Samba Zugriff GDT/PDF/wartezimmer-GDT: anonym (guest), schreibbar"
    else
      echo "Samba Zugriff GDT/PDF:  anonym (guest), schreibbar"
    fi
  fi
  echo
  echo "Samba Admin (webroot-wlan/webroot-lan/SSH/sudo):  ${ADMIN_USER}"
  echo "Admin Passwort (generiert):       ${admin_pw}"
  echo
  if (( ${#EXTRA_USERS_LIST[@]} > 0 )); then
    echo "Zusätzliche Windows-/Samba-User:"
    local idx=0
    for u in "${EXTRA_USERS_LIST[@]}"; do
      if [[ "${EXTRA_USERS_MODE[$idx]}" == "generated" ]]; then
        echo "  - ${u}: Passwort (generiert) = ${EXTRA_USERS_PW[$idx]}"
      else
        echo "  - ${u}: Passwort (manuell gesetzt, nicht angezeigt)"
      fi
      idx=$((idx+1))
    done
    echo
  fi
  echo "======================================================"
  echo

  local del_user=""
  if ask_yes_no "Soll ein bestehender Systembenutzer gelöscht werden?" "n"; then
    read -r -p "Benutzername zum Löschen [pi]: " del_user
    del_user="${del_user:-pi}"
    del_user="$(echo "$del_user" | sed -e 's/\r$//' -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"

    if [[ -z "$del_user" ]]; then
      warn "Leerer Benutzername – überspringe Löschung."
      del_user=""
    elif [[ "$del_user" == "root" ]]; then
      warn "root darf nicht gelöscht werden – überspringe."
      del_user=""
    elif ! id -u "$del_user" >/dev/null 2>&1; then
      warn "Benutzer '${del_user}' existiert nicht – überspringe."
      del_user=""
    fi
  fi

  step "Reboot (in 10 Sekunden) und optional Benutzer löschen"

  if [[ -n "$del_user" ]]; then
    log "Lösche Benutzer '${del_user}' ..."
    if userdel -r "$del_user" >/dev/null 2>&1; then
      ok "Benutzer gelöscht: ${del_user}"
    else
      warn "userdel für '${del_user}' fehlgeschlagen (Benutzer in Benutzung?) – plane Löschung nach dem nächsten Boot."
      install_delete_user_on_boot "$del_user"
      ok "Benutzerlöschung für nächsten Boot eingeplant: ${del_user}"
    fi
  else
    log "Keine Benutzerlöschung gewählt."
  fi

  schedule_reboot_10s
  ok "Reboot gestartet (in 10 Sekunden)"
  log "Fertig. Reboot erfolgt gleich."
}

main "$@"
