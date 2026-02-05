#!/usr/bin/env bash
#
# fragebogenpi.sh
# Projekt: fragebogenpi
# Autor: Thomas Kienzle
#
# Version: 1.5.1
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

# -------------------------
# UI / Logging
# -------------------------
VERSION="1.5.1"
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
  echo
  echo "[fragebogenpi] Es wurde eine bestehende Installation gefunden: ${SHARE_BASE}"
  echo "Was soll ich tun?"
  echo "  1) Vollständige Neu-Konfiguration (setzt Passwörter neu, richtet Dienste/Firewall/Samba/AP/PHP neu ein)"
  echo "  2) Nur Webroot-Update (lädt/aktualisiert nur die Programme im Webroot; bestehende Dateien werden überschrieben)"
  while true; do
    read -r -p "Auswahl [1/2]: " answer
    case "$answer" in
      1) echo "full"; return 0 ;;
      2) echo "webroot"; return 0 ;;
      *) echo "Bitte 1 oder 2 eingeben." ;;
    esac
  done
}

ask_password_twice() {
  local prompt="$1"
  local p1="" p2=""
  while true; do
    read -r -s -p "${prompt}: " p1
    echo
    read -r -s -p "${prompt} (Wiederholung): " p2
    echo
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
    # Best effort: falls ein existierender User eine falsche Shell hat und wir eine andere wünschen
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
  # Erlaubt: relative Pfade ohne .. und ohne führenden /
  # Blockiert: "..", "/abs", "\0", leere Strings
  local p="$1"
  [[ -n "$p" ]] || die "Bootstrap-Liste enthält eine leere Zeile nach Trimming (sollte nicht passieren)."
  [[ "$p" != /* ]] || die "Unsicherer Pfad in Bootstrap-Liste (absolut): '$p'"
  [[ "$p" != *$'\0'* ]] || die "Unsicherer Pfad in Bootstrap-Liste (NUL): '$p'"
  if echo "$p" | grep -Eq '(^|/)\.\.(/|$)'; then
    die "Unsicherer Pfad in Bootstrap-Liste (..): '$p'"
  fi
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
  local use_auth="$1"                # "yes"|"no"
  local samba_pw="$2"                # wenn use_auth=yes
  local admin_pw="$3"                # immer
  local extra_users_csv="$4"         # "u1 u2 u3" (optional)

  log "Konfiguriere Samba..."

  local smbconf="/etc/samba/smb.conf"
  backup_file "$smbconf"

  cat > "$smbconf" <<EOF
[global]
   workgroup = WORKGROUP
   server string = fragebogenpi samba server
   security = user
   map to guest = Bad User
   guest account = nobody

   # SMB nur im LAN anbieten (eth0)
   interfaces = lo ${LAN_INTERFACE}
   bind interfaces only = yes

   server min protocol = SMB2
   server max protocol = SMB3

   log file = /var/log/samba/log.%m
   max log size = 1000

   create mask = 0664
   directory mask = 2775
   force create mode = 0664
   force directory mode = 2775
EOF

  # valid users Liste für GDT/PDF (nur relevant bei Passwortschutz)
  local valid_users_gdtpdf=""
  if [[ "$use_auth" == "yes" ]]; then
    valid_users_gdtpdf="${SAMBA_USER}"
    if [[ -n "${extra_users_csv// }" ]]; then
      valid_users_gdtpdf="${valid_users_gdtpdf} ${extra_users_csv}"
    fi
  fi

  if [[ "$use_auth" == "no" ]]; then
    cat >> "$smbconf" <<EOF

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
    cat >> "$smbconf" <<EOF

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

    log "Lege Benutzer '${SAMBA_USER}' an (falls nicht vorhanden) und setze Samba-Passwort..."
    ensure_linux_user "${SAMBA_USER}" "/usr/sbin/nologin"
    (echo "${samba_pw}"; echo "${samba_pw}") | smbpasswd -a -s "${SAMBA_USER}"
    smbpasswd -e "${SAMBA_USER}" >/dev/null 2>&1 || true
  fi

  cat >> "$smbconf" <<EOF

[WEBROOT]
   path = ${WEBROOT}
   browseable = yes
   read only = no
   guest ok = no
   valid users = ${ADMIN_USER}
   force user = www-data
   force group = www-data
EOF

  # Admin: Linux-User mit Shell + sudo + Samba-Passwort
  log "Lege Admin-Benutzer '${ADMIN_USER}' an (falls nicht vorhanden), setze Linux+Samba-Passwort und gebe sudo..."
  ensure_linux_user "${ADMIN_USER}" "/bin/bash"

  # sudo Rechte
  if getent group sudo >/dev/null 2>&1; then
    usermod -aG sudo "${ADMIN_USER}" >/dev/null 2>&1 || true
  fi

  # Linux Passwort setzen
  echo "${ADMIN_USER}:${admin_pw}" | chpasswd

  # Samba Passwort setzen
  (echo "${admin_pw}"; echo "${admin_pw}") | smbpasswd -a -s "${ADMIN_USER}"
  smbpasswd -e "${ADMIN_USER}" >/dev/null 2>&1 || true

  systemctl enable --now smbd nmbd || true
  systemctl restart smbd nmbd || true

  ok "Samba läuft (nur LAN/eth0). Admin hat SSH+sudo."
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

  systemctl enable --now dnsmasq || true
  systemctl restart dnsmasq || print_service_debug_and_die "dnsmasq.service"

  systemctl unmask hostapd >/dev/null 2>&1 || true
  systemctl enable --now hostapd || true
  systemctl restart hostapd || print_service_debug_and_die "hostapd.service"

  ok "AP/DHCP aktiv"
}

setup_https_if_requested() {
  step "Webserver konfigurieren (HTTP/HTTPS)"
  local mode="$1"

  if [[ "$mode" == "http" ]]; then
    log "HTTP-only gewählt. HTTPS wird nicht aktiviert."
    ok "Apache HTTP aktiv"
    return 0
  fi

  log "HTTPS gewählt. Erzeuge self-signed Zertifikat (gültig bis 2050) und aktiviere Apache SSL..."

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

  a2enmod ssl >/dev/null
  a2enmod rewrite >/dev/null

  local ssl_site="/etc/apache2/sites-available/default-ssl.conf"
  backup_file "$ssl_site"
  sed -i "s|^\s*SSLCertificateFile\s\+.*|SSLCertificateFile ${SSL_CRT}|g" "$ssl_site"
  sed -i "s|^\s*SSLCertificateKeyFile\s\+.*|SSLCertificateKeyFile ${SSL_KEY}|g" "$ssl_site"

  a2ensite default-ssl >/dev/null
  systemctl reload apache2

  ok "Apache HTTPS aktiv (self-signed)"
}

setup_firewall_nftables_wlan_only() {
  step "Firewall: nur WLAN beschränken, LAN unberührt lassen (kein Routing)"

  local nftconf="/etc/nftables.conf"
  backup_file "$nftconf"

  cat > "$nftconf" <<EOF
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0;
    policy accept;

    iif "${AP_INTERFACE}" ct state established,related accept
    iif "${AP_INTERFACE}" tcp dport 22 drop
    iif "${AP_INTERFACE}" udp dport { 67, 68 } accept
    iif "${AP_INTERFACE}" udp dport 53 accept
    iif "${AP_INTERFACE}" tcp dport { 80, 443 } accept
    iif "${AP_INTERFACE}" drop
  }

  chain forward {
    type filter hook forward priority 0;
    policy drop;
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
  sysctl --system >/dev/null

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

  ok "PHP Optionen gesetzt (Apache + CLI) für PHP ${php_ver}"
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

download_bootstrap_files_to_webroot() {
  step "Webroot Bootstrap: Dateiliste laden und Dateien herunterladen"

  ensure_command curl curl

  local base_url
  base_url="$(echo "$BOOTSTRAP_URL" | sed 's#^\(.*\)/[^/]*$#\1#')"

  log "Lade Bootstrap-Liste:"
  log "  ${BOOTSTRAP_URL}"

  local tmp_list
  tmp_list="$(mktemp)"
  trap 'rm -f "$tmp_list"' EXIT

  curl -fsSL "$BOOTSTRAP_URL" -o "$tmp_list" || die "Download fehlgeschlagen: bootstrap"

  local count_total=0
  local count_skipped=0
  local count_ok=0

  while IFS= read -r raw || [[ -n "$raw" ]]; do
    # trim
    local line
    line="$(echo "$raw" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"

    # ignore empty + comments
    if [[ -z "$line" ]] || [[ "$line" == \#* ]]; then
      count_skipped=$((count_skipped+1))
      continue
    fi

    count_total=$((count_total+1))

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

create_additional_samba_users() {
  # args:
  # 1) space-separated usernames (may be empty)
  # 2) name of bash array of passwords (parallel)
  # 3) name of bash array of flags (parallel) "generated"|"manual"
  local users_csv="$1"
  local -n pw_arr="$2"
  local -n mode_arr="$3"

  [[ -n "${users_csv// }" ]] || return 0

  step "Zusätzliche Windows-/Samba-User anlegen"

  local i=0
  for u in $users_csv; do
    # minimal sanity
    if [[ -z "$u" ]] || [[ "$u" == "root" ]]; then
      die "Ungültiger Username in Zusatzliste: '$u'"
    fi

    log "Lege Benutzer '${u}' an (Linux + Samba)..."
    ensure_linux_user "$u" "/usr/sbin/nologin"

    local pw="${pw_arr[$i]}"
    (echo "${pw}"; echo "${pw}") | smbpasswd -a -s "${u}"
    smbpasswd -e "${u}" >/dev/null 2>&1 || true

    ok "User '${u}' angelegt/aktiviert (Samba)"
    i=$((i+1))
  done
}

write_credentials_file_if_requested() {
  local want="$1"                 # yes/no
  local web_mode="$2"             # http/https
  local protect_shares="$3"       # yes/no
  local wifi_pw="$4"
  local samba_pw="$5"             # maybe empty
  local admin_pw="$6"
  local lan_ip="$7"
  local lan_mac="$8"
  local ap_mac="$9"
  local extra_users_csv="${10}"
  local -n extra_pw_arr="${11}"
  local -n extra_mode_arr="${12}"

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
    echo "  - http(s)://fragebogenpi/        (nur wenn Router/DNS Name auflöst)"
    echo "  - http(s)://fragebogenpi.local/  (mDNS/Bonjour)"
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
    echo
    echo "== Samba (nur LAN) =="
    echo "\\\\<LAN-IP>\\GDT      -> ${SHARE_GDT}"
    echo "\\\\<LAN-IP>\\PDF      -> ${SHARE_PDF}"
    echo "\\\\<LAN-IP>\\WEBROOT  -> ${WEBROOT}"
    echo
    if [[ "$protect_shares" == "yes" ]]; then
      echo "User (GDT/PDF): ${SAMBA_USER}"
      echo "Passwort:       ${samba_pw}"
    else
      echo "GDT/PDF Zugriff: anonym (guest), schreibbar"
    fi
    echo
    echo "Admin (WEBROOT/SSH/sudo): ${ADMIN_USER}"
    echo "Admin Passwort (generiert):  ${admin_pw}"
    echo
    if [[ -n "${extra_users_csv// }" ]]; then
      echo "== Zusätzliche Windows-/Samba-User =="
      local idx=0
      for u in $extra_users_csv; do
        if [[ "${extra_mode_arr[$idx]}" == "generated" ]]; then
          echo "- ${u}: Passwort (generiert) = ${extra_pw_arr[$idx]}"
        else
          echo "- ${u}: Passwort (manuell gesetzt, nicht angezeigt)"
        fi
        idx=$((idx+1))
      done
      echo
    fi
    echo "== Bootstrap =="
    echo "Quelle: ${BOOTSTRAP_URL}"
    echo "Hinweis: Dateien wurden ins Webroot geladen (ggf. Unterverzeichnisse)."
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
  # Modus 2: Nur Webroot-Update (Bootstrap-Dateien)
  # ------------------------------------------------------
  if [[ "$mode" == "webroot" ]]; then
    step "Modus: Nur Webroot-Update"
    log "Es werden NUR die Bootstrap-Dateien ins Webroot geladen."
    log "Netzwerk/Samba/Firewall/Passwörter bleiben unverändert."

    install_packages_webroot_only
    setup_webroot_perms
    download_bootstrap_files_to_webroot

    step "Abschluss (Webroot-Update)"
    echo
    echo "Webroot-Update abgeschlossen."
    echo "Quelle (Bootstrap): ${BOOTSTRAP_URL}"
    echo "Ziel (Webroot):     ${WEBROOT}"
    echo "Hinweis: Bestehende Dateien wurden überschrieben."
    echo
    exit 0
  fi

  # ------------------------------------------------------
  # Modus 1: Vollinstallation / Neu-Konfiguration
  # ------------------------------------------------------
  step "Konfiguration abfragen"
  local wifi_pw web_mode protect_shares samba_pw admin_pw save_creds
  wifi_pw="$(rand_pw)"
  web_mode="$(ask_choice_http_https)"

  protect_shares="no"
  samba_pw=""
  if ask_yes_no "Samba-Shares GDT/PDF mit Passwort schützen (User '${SAMBA_USER}')?" "y"; then
    protect_shares="yes"
    samba_pw="$(rand_pw)"
  fi

  admin_pw="$(rand_pw)"

  save_creds="no"
  if ask_yes_no "Zugangsdaten zusätzlich als Datei ins PDF-Share schreiben (BITTE danach löschen)?" "n"; then
    save_creds="yes"
  fi

  # Zusätzliche Windows-/Samba-User (für Gruppenrichtlinien etc.)
  local extra_users_csv=""
  read -r -p "Zusätzliche Windows-/Samba-User anlegen? (Leer=keine, Trennung per Leerzeichen): " extra_users_csv
  extra_users_csv="$(echo "$extra_users_csv" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"

  declare -a EXTRA_USERS_PW=()
  declare -a EXTRA_USERS_MODE=() # "generated"|"manual"

  if [[ -n "${extra_users_csv// }" ]]; then
    for u in $extra_users_csv; do
      if [[ -z "$u" ]] || [[ "$u" == "root" ]]; then
        die "Ungültiger Username: '$u'"
      fi

      local choice=""
      while true; do
        read -r -p "User '${u}': Passwort eingeben (1) oder generieren (2)? [2]: " choice
        choice="${choice:-2}"
        case "$choice" in
          1)
            EXTRA_USERS_PW+=("$(ask_password_twice "Passwort für '${u}'")")
            EXTRA_USERS_MODE+=("manual")
            break
            ;;
          2)
            EXTRA_USERS_PW+=("$(rand_pw)")
            EXTRA_USERS_MODE+=("generated")
            break
            ;;
          *)
            echo "Bitte 1 oder 2 eingeben."
            ;;
        esac
      done
    done
  fi

  ok "Eingaben übernommen"

  install_packages_full
  set_hostname
  setup_share_dirs
  setup_webroot_perms
  setup_samba "$protect_shares" "$samba_pw" "$admin_pw" "$extra_users_csv"

  # Zusätzliche Samba-User anlegen (optional)
  if [[ -n "${extra_users_csv// }" ]]; then
    create_additional_samba_users "$extra_users_csv" EXTRA_USERS_PW EXTRA_USERS_MODE
  fi

  configure_ap_ip
  setup_ap_hostapd_dnsmasq "$wifi_pw"
  setup_https_if_requested "$web_mode"

  setup_firewall_nftables_wlan_only
  ensure_sshd_normal_listen

  configure_php_settings
  download_bootstrap_files_to_webroot
  enable_auto_updates

  # Abschlussdaten
  local lan_ip lan_mac ap_mac
  lan_ip="$(get_iface_ipv4 "${LAN_INTERFACE}")"
  lan_mac="$(get_iface_mac "${LAN_INTERFACE}")"
  ap_mac="$(get_iface_mac "${AP_INTERFACE}")"

  write_credentials_file_if_requested \
    "$save_creds" "$web_mode" "$protect_shares" "$wifi_pw" "$samba_pw" "$admin_pw" \
    "$lan_ip" "$lan_mac" "$ap_mac" \
    "$extra_users_csv" EXTRA_USERS_PW EXTRA_USERS_MODE

  step "Abschlussinformationen"
  log "Fertig."

  echo
  echo "==================== ZUGANGSDATEN ===================="
  echo "Hostname (System):      ${HOSTNAME_FQDN}"
  echo
  echo "Namensauflösung / Erreichbarkeit:"
  echo "  - http(s)://fragebogenpi/        -> nur wenn Router/DNS Hostnamen auflöst"
  echo "  - http(s)://fragebogenpi.local/  -> mDNS/Bonjour (empfohlen)"
  echo "  - http(s)://<IP-Adresse>/        -> funktioniert immer"
  echo
  echo "WLAN SSID:        ${AP_SSID}"
  echo "WLAN Passwort:    ${wifi_pw}"
  echo "WLAN IP (Pi):     ${AP_IP}"
  echo "Webserver (WLAN): http://${AP_IP}/"
  if [[ "$web_mode" == "https" ]]; then
    echo "Webserver (WLAN): https://${AP_IP}/  (self-signed Warnung ist normal)"
  fi
  echo
  echo "LAN IP (aktuell): ${lan_ip:-<unbekannt>}"
  echo "LAN MAC (eth0):   ${lan_mac:-<unbekannt>}"
  echo "WLAN MAC (wlan0): ${ap_mac:-<unbekannt>}"
  echo
  echo "WICHTIG:"
  echo "  Im Router sollte für '${HOSTNAME_FQDN}' eine feste IP / DHCP-Reservation gesetzt werden."
  echo "  Nutze dafür die LAN MAC-Adresse (eth0) von oben."
  echo
  echo "Samba Shares (nur LAN/eth0, nicht WLAN):"
  echo "  \\\\<LAN-IP-des-Pi>\\GDT      -> ${SHARE_GDT}"
  echo "  \\\\<LAN-IP-des-Pi>\\PDF      -> ${SHARE_PDF}"
  echo "  \\\\<LAN-IP-des-Pi>\\WEBROOT  -> ${WEBROOT}"
  echo
  if [[ "$protect_shares" == "yes" ]]; then
    echo "Samba User (GDT/PDF):   ${SAMBA_USER}"
    echo "Samba Passwort:         ${samba_pw}"
  else
    echo "Samba Zugriff GDT/PDF:  anonym (guest), schreibbar"
  fi
  echo
  echo "Samba Admin (WEBROOT/SSH/sudo):  ${ADMIN_USER}"
  echo "Admin Passwort (generiert):       ${admin_pw}"
  echo
  if [[ -n "${extra_users_csv// }" ]]; then
    echo "Zusätzliche Windows-/Samba-User:"
    idx=0
    for u in $extra_users_csv; do
      if [[ "${EXTRA_USERS_MODE[$idx]}" == "generated" ]]; then
        echo "  - ${u}: Passwort (generiert) = ${EXTRA_USERS_PW[$idx]}"
      else
        echo "  - ${u}: Passwort (manuell gesetzt, nicht angezeigt)"
      fi
      idx=$((idx+1))
    done
    echo
  fi
  echo "Bootstrap:"
  echo "  Quelle: ${BOOTSTRAP_URL}"
  echo "  Ziel:   ${WEBROOT} (inkl. Unterverzeichnisse, falls gelistet)"
  echo
  echo "PHP Pakete:"
  echo "  - php-gd"
  echo "  - php-yaml"
  echo
  echo "PHP Optionen:"
  echo "  upload_max_filesize=${PHP_UPLOAD_MAX}"
  echo "  post_max_size=${PHP_POST_MAX}"
  echo "  max_file_uploads=${PHP_MAX_UPLOADS}"
  echo "  max_execution_time=${PHP_MAX_EXEC}"
  echo "  max_input_time=${PHP_MAX_INPUT}"
  echo
  echo "Auto-Update:"
  echo "  unattended-upgrades ist installiert und aktiviert."
  echo
  if [[ "$save_creds" == "yes" ]]; then
    echo "Zugangsdaten-Datei:"
    echo "  ${CRED_FILE}"
    echo "  (BITTE NACH ÜBERNAHME LÖSCHEN!)"
    echo
  fi
  echo "Hinweis (Variante A):"
  echo "  PDF liegt außerhalb des Webroots: ${SHARE_PDF}"
  echo "  -> NICHT direkt per HTTP/HTTPS erreichbar, aber PHP (www-data) kann schreiben."
  echo
  echo "Hinweis SSH:"
  echo "  sshd lauscht normal auf allen Interfaces."
  echo "  Auf WLAN (wlan0) wird SSH per Firewall blockiert; LAN bleibt unberührt."
  echo "======================================================"
  echo

  # ------------------------------------------------------
  # NACH der Ausgabe: optionale Benutzerlöschung
  # ------------------------------------------------------
  local del_user=""

  if ask_yes_no "Soll ein bestehender Systembenutzer gelöscht werden?" "n"; then
    read -r -p "Benutzername zum Löschen [pi]: " del_user
    del_user="${del_user:-pi}"
    del_user="$(echo "$del_user" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"

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

  # ------------------------------------------------------
  # Ganz am Ende: Reboot in 10 Sekunden planen, dann optional löschen (letzter Schritt)
  # ------------------------------------------------------
  step "Reboot (in 10 Sekunden) und optional Benutzer löschen"

  log "Plane Reboot in 10 Sekunden..."
  shutdown -r +0.166 "fragebogenpi: Reboot in 10 Sekunden" || true
  ok "Reboot geplant (10 Sekunden)"

  if [[ -n "$del_user" ]]; then
    log "Lösche Benutzer '${del_user}' (userdel -r) ..."
    userdel -r "$del_user" || warn "userdel für '${del_user}' fehlgeschlagen (möglicherweise in Benutzung); Reboot folgt ohnehin."
    ok "Benutzerlöschung angestoßen: ${del_user}"
  else
    log "Keine Benutzerlöschung gewählt."
  fi

  log "Fertig. Reboot erfolgt gleich."
}

main "$@"
