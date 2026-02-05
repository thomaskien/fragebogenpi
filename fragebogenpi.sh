#!/usr/bin/env bash
#
# fragebogenpi.sh
# Projekt: fragebogenpi
# Autor: Thomas Kienzle
#
# Version: 1.5.4
#
# =========================
# Changelog (vollständig)
# =========================
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
#   * Bugfix Reboot: shutdown-Zeitformat korrigiert; Reboot jetzt robust via "sleep 10; systemctl reboot/reboot" (nohup)
#   * Bugfix User-Löschung: wenn User gerade benutzt wird (oder aktueller Login-User), wird Löschung auf nächsten Boot verschoben (systemd oneshot)
#   * Bugfix tmp_list: Trap von EXIT auf RETURN umgestellt (verhindert "unbound variable" bei set -u)
#
# =========================
#
set -euo pipefail

# -------------------------
# Konfiguration (Defaults)
# -------------------------
AP_SSID="fragebogenpi"
HOSTNAME_FQDN="fragebogenpi"

AP_INTERFACE="wlan0"
LAN_INTERFACE="eth0"

AP_SUBNET_CIDR="10.23.0.0/24"
AP_IP="10.23.0.1"
AP_DHCP_START="10.23.0.50"
AP_DHCP_END="10.23.0.150"
AP_NETMASK="255.255.255.0"

WEBROOT="/var/www/html"

# Variante A: Shares außerhalb des Webroots
SHARE_BASE="/srv/fragebogenpi"
SHARE_GDT="${SHARE_BASE}/GDT"
SHARE_PDF="${SHARE_BASE}/PDF"
CRED_FILE="${SHARE_PDF}/zugangsdaten_fragebogenpi_bitte_loeschen.txt"

# Samba-User
SAMBA_USER="fragebogenpi"   # optional (für GDT/PDF, wenn Passwortschutz gewählt)
ADMIN_USER="admin"          # immer vorhanden für WEBROOT Share

# HTTPS (optional)
SSL_DIR="/etc/ssl/fragebogenpi"
SSL_KEY="${SSL_DIR}/fragebogenpi.key"
SSL_CRT="${SSL_DIR}/fragebogenpi.crt"

# AP IP helper/service
AP_IP_SERVICE="/etc/systemd/system/fragebogenpi-ap-ip.service"
AP_IP_HELPER="/usr/local/sbin/fragebogenpi-ap-ip.sh"

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

# -------------------------
# UI / Logging
# -------------------------
VERSION="1.5.4"
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
  echo "Hinweis: Auswahl 2 überschreibt Dateien im Webroot (Programme/Bootstrap), sonst nichts." >&2
  echo "Was soll ich tun?" >&2
  echo "  1) Vollständige Neu-Konfiguration (setzt Passwörter neu, richtet Dienste/Firewall/Samba/AP/PHP neu ein)" >&2
  echo "  2) Nur Webroot-Update (lädt/aktualisiert nur die Programme im Webroot; bestehende Dateien werden überschrieben)" >&2
  echo "  3) Nur User hinzufügen (legt nur zusätzliche Windows-/Samba-User an; sonst keine Änderungen)" >&2
  while true; do
    read -r -p "Auswahl [1/2/3]: " answer
    case "$answer" in
      1) echo "full"; return 0 ;;
      2) echo "webroot"; return 0 ;;
      3) echo "users"; return 0 ;;
      *) echo "Bitte 1, 2 oder 3 eingeben." >&2 ;;
    esac
  done
}

ask_password_twice() {
  local prompt="$1"
  local p1="" p2=""
  while true; do
    read -r -s -p "${prompt}: " p1
    printf '\n'
    read -r -s -p "${prompt} (Wiederholung): " p2
    printf '\n'
    [[ -n "$p1" ]] || { echo "Passwort darf nicht leer sein."; continue; }
    if [[ "$p1" == "$p2" ]]; then
      echo "$p1"
      return 0
    fi
    echo "Passwörter stimmen nicht überein. Bitte erneut."
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

if [[ ! -f "$MARKER" ]]; then
  exit 0
fi

USER_TO_DEL="$(cat "$MARKER" | tr -d '\r' | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"
if [[ -z "$USER_TO_DEL" ]] || [[ "$USER_TO_DEL" == "root" ]]; then
  rm -f "$MARKER" || true
  systemctl disable "$SERVICE" >/dev/null 2>&1 || true
  exit 0
fi

# best effort: kill any remaining processes of that user
pkill -u "$USER_TO_DEL" >/dev/null 2>&1 || true
sleep 0.5

userdel -r "$USER_TO_DEL" >/dev/null 2>&1 || true

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

schedule_reboot_10s() {
  log "Reboot in 10 Sekunden..."
  # robust: detach reboot command from current shell
  nohup bash -c 'sleep 10; systemctl reboot >/dev/null 2>&1 || /sbin/reboot >/dev/null 2>&1 || reboot >/dev/null 2>&1' >/dev/null 2>&1 &
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
    samba \
    hostapd dnsmasq \
    nftables \
    acl openssl \
    avahi-daemon \
    python3 \
    curl \
    unattended-upgrades \
    sudo

  ok "Pakete installiert (inkl. php-gd, php-yaml, curl, unattended-upgrades, sudo)"
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
  DEBIAN_FRONTEND=noninteractive apt-get install -y samba
  ok "samba ist verfügbar (smbpasswd)"
}

set_hostname() {
  step "Hostname setzen und mDNS aktivieren"
  log "Setze Hostname auf '${HOSTNAME_FQDN}'..."
  if command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "${HOSTNAME_FQDN}"
  else
    echo "${HOSTNAME_FQDN}" > /etc/hostname
    hostname "${HOSTNAME_FQDN}" || true
  fi

  if ! grep -qE "127\.0\.1\.1\s+${HOSTNAME_FQDN}\b" /etc/hosts; then
    echo "127.0.1.1 ${HOSTNAME_FQDN}" >> /etc/hosts
  fi

  systemctl enable --now avahi-daemon >/dev/null 2>&1 || true
  systemctl restart avahi-daemon >/dev/null 2>&1 || true

  ok "Hostname/mDNS konfiguriert"
}

setup_share_dirs() {
  step "Share-Verzeichnisse (Variante A) erstellen und Rechte setzen"
  log "Erstelle Share-Verzeichnisse außerhalb des Webroots: ${SHARE_BASE}"
  mkdir -p "$SHARE_GDT" "$SHARE_PDF"

  chown -R www-data:www-data "$SHARE_BASE"
  chmod -R 2775 "$SHARE_BASE"

  setfacl -R -m u:www-data:rwx "$SHARE_GDT" "$SHARE_PDF" || true
  setfacl -R -d -m u:www-data:rwx "$SHARE_GDT" "$SHARE_PDF" || true

  ok "Shares liegen außerhalb des Webroots (nicht direkt per Web erreichbar)"
}

setup_webroot_perms() {
  step "Webroot Rechte für PHP und Samba-Admin vorbereiten"
  mkdir -p "$WEBROOT"
  chown -R www-data:www-data "$WEBROOT"
  chmod -R 2775 "$WEBROOT"

  setfacl -R -m u:www-data:rwx "$WEBROOT" || true
  setfacl -R -d -m u:www-data:rwx "$WEBROOT" || true

  ok "Webroot ist für www-data schreibbar"
}

setup_samba() {
  step "Samba konfigurieren (LAN: GDT/PDF optional, WEBROOT nur admin)"
  local use_auth="$1"
  local samba_pw="$2"
  local admin_pw="$3"
  local extra_users_csv="$4"

  log "Konfiguriere Samba..."

  local smbconf="/etc/samba/smb.conf"
  backup_file didn’t change? # placeholder
}
