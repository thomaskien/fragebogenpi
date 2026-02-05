#!/usr/bin/env bash
#
# fragebogenpi.sh
# Projekt: fragebogenpi.de
# Autor: Thomas Kienzle
#
# Version: 1.6.2
#
# =========================
# Changelog (vollständig)
# =========================
#
# - 1.0 (2026-01-31)
#   * Initiale Version (Apache+PHP, Samba GDT/PDF, hostapd+dnsmasq, WLAN isoliert, nftables)
#
# - 1.1 (2026-01-31)
#   * Hostname "fragebogenpi", mDNS (avahi), Abschlussausgabe IP/MAC, Hinweis feste IP im Router
#
# - 1.1.1 (2026-01-31)
#   * Klarstellung Erreichbarkeit: fragebogenpi / fragebogenpi.local / IP
#
# - 1.1.2 (2026-01-31)
#   * Bugfix: Passwort-Generator robust (kein EXIT=141 bei pipefail)
#   * apt-get upgrade vor Paketinstallation ergänzt
#
# - 1.1.3 (2026-01-31)
#   * dhcpcd optional: AP-IP robuster (NetworkManager unmanaged + systemd oneshot wenn nötig)
#
# - 1.1.4 (2026-01-31)
#   * dnsmasq robust: Port 53 belegt -> DHCP-only (port=0)
#   * Bei Fehlern automatische systemctl/journalctl Diagnose
#
# - 1.2 (2026-01-31)
#   * Variante A: Shares außerhalb Webroot (/srv/fragebogenpi/GDT, /srv/fragebogenpi/PDF)
#   * Firewall: LAN ungefiltert, WLAN strikt (nur DHCP/DNS/HTTP/HTTPS), Forwarding drop, ip_forward=0
#   * Installer-UI mit Step-Blöcken
#
# - 1.3 (2026-01-31)
#   * SSH-Strategie: sshd "normal", Block nur per Firewall im WLAN
#   * Samba WEBROOT Share (admin-only)
#
# - 1.4.0 (2026-01-31)
#   * php-gd, PHP Limits via 99-fragebogenpi.ini (apache2+cli)
#   * unattended-upgrades als Paket + aktiviert
#
# - 1.4.1 (2026-01-31)
#   * php-yaml
#   * Optional Zugangsdaten-Datei im PDF-Share
#
# - 1.5.0 (2026-02-05)
#   * Bootstrap-Downloads aus Datei:
#       https://raw.githubusercontent.com/thomaskien/fragebogenpi/refs/heads/main/bootstrap
#     (relative Pfade; Kommentare/leer ignoriert; .. und absolute Pfade blockiert)
#   * Wenn /srv/fragebogenpi existiert: Moduswahl (Voll-Konfig vs Webroot-Update)
#
# - 1.6.0 (2026-02-05)
#   * Projekt umbenannt: "fragebogenpi.de"
#   * Admin-User: Passwort manuell oder generiert; Zugriff aufs Webroot
#   * Samba-User: Passwort manuell oder generiert; Hinweis zu Windows/Guest-Policies
#   * WEBROOT Share: optional als Gast schreibbar (nicht empfohlen, Default N)
#   * Bootstrap: akzeptiert auch "./datei" (Normalisierung)
#
# - 1.6.1 (2026-02-05)
#   * Fix Aussperren: Admin wird NICHT mehr versehentlich zu nologin gemacht
#   * SSH-safe Ablauf: nftables erst NACH Zugangsdaten-Ausgabe aktivieren; danach Reboot
#   * Nach Zugangsdaten: Rückfrage "User löschen?" (Default nein, Vorschlag "pi")
#   * Reboot am Ende
#
# - 1.6.2 (2026-02-05)
#   * Bugfix: Heredoc-Schreibvorgänge robust gemacht (umgeht TTY/stty-Effekte)
#       - Konfigdateien werden nun via `tee` geschrieben statt `cat > file <<EOF`
#   * Safety: stty wird beim Exit/Interrupt zuverlässig zurückgesetzt (trap)
#
# =========================

set -euo pipefail

# -------------------------
# Konfiguration
# -------------------------
PROJECT_NAME="fragebogenpi.de"
HOSTNAME_FQDN="fragebogenpi"

AP_SSID="fragebogenpi"
AP_INTERFACE="wlan0"
LAN_INTERFACE="eth0"

AP_IP="10.23.0.1"
AP_DHCP_START="10.23.0.50"
AP_DHCP_END="10.23.0.150"
AP_NETMASK="255.255.255.0"

WEBROOT="/var/www/html"

SHARE_BASE="/srv/fragebogenpi"
SHARE_GDT="${SHARE_BASE}/GDT"
SHARE_PDF="${SHARE_BASE}/PDF"
CRED_FILE="${SHARE_PDF}/zugangsdaten_fragebogenpi_bitte_loeschen.txt"

DEFAULT_SAMBA_USER="fragebogenpi"
ADMIN_USER="admin"

SSL_DIR="/etc/ssl/fragebogenpi"
SSL_KEY="${SSL_DIR}/fragebogenpi.key"
SSL_CRT="${SSL_DIR}/fragebogenpi.crt"

AP_IP_SERVICE="/etc/systemd/system/fragebogenpi-ap-ip.service"
AP_IP_HELPER="/usr/local/sbin/fragebogenpi-ap-ip.sh"

BOOTSTRAP_URL="https://raw.githubusercontent.com/thomaskien/fragebogenpi/refs/heads/main/bootstrap"

PHP_UPLOAD_MAX="25M"
PHP_POST_MAX="250M"
PHP_MAX_UPLOADS="30"
PHP_MAX_EXEC="120"
PHP_MAX_INPUT="120"

VERSION="1.6.2"
STEP_NO=0
TTY="/dev/tty"

# -------------------------
# Logging / UI
# -------------------------
log()  { echo -e "[${PROJECT_NAME}] $*"; }
warn() { echo -e "[${PROJECT_NAME}][WARN] $*" >&2; }
die()  { echo -e "[${PROJECT_NAME}][ERROR] $*" >&2; exit 1; }

banner() {
  echo
  echo "## ${PROJECT_NAME} v${VERSION} von Thomas Kienzle"
  echo "##"
  echo "## Starte installation..."
  echo
}

step() {
  STEP_NO=$((STEP_NO+1))
  echo
  echo "======================================================"
  echo "== Schritt ${STEP_NO}: $*"
  echo "======================================================"
}

ok() { echo "[OK] $*"; }

# -------------------------
# TTY Helpers
# -------------------------
tty_out()   { printf "%b" "$*" >"$TTY"; }
tty_outln() { printf "%b\n" "$*" >"$TTY"; }

tty_read() {
  local prompt="$1"
  local __varname="$2"
  local __val=""
  tty_out "$prompt"
  IFS= read -r __val <"$TTY"
  printf -v "$__varname" "%s" "$__val"
}

tty_read_silent() {
  local prompt="$1"
  local __varname="$2"
  local __val=""
  tty_out "$prompt"
  stty -echo <"$TTY" || true
  IFS= read -r __val <"$TTY" || true
  stty echo <"$TTY" || true
  tty_outln ""
  printf -v "$__varname" "%s" "$__val"
}

ask_yes_no_tty() {
  local prompt="$1"
  local def="$2"
  local ans=""
  while true; do
    if [[ "$def" == "y" ]]; then
      tty_read "${prompt} [Y/n]: " ans
      ans="${ans:-Y}"
    else
      tty_read "${prompt} [y/N]: " ans
      ans="${ans:-N}"
    fi
    case "${ans,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) tty_outln "Bitte y oder n eingeben." ;;
    esac
  done
}

ask_choice_http_https_tty() {
  local ans=""
  while true; do
    tty_read "Webserver: Nur HTTP (1) oder HTTP+HTTPS (2)? [1/2]: " ans
    case "$ans" in
      1) echo "http"; return 0 ;;
      2) echo "https"; return 0 ;;
      *) tty_outln "Bitte 1 oder 2 eingeben." ;;
    esac
  done
}

ask_choice_existing_install_tty() {
  local ans=""
  tty_outln ""
  tty_outln "[${PROJECT_NAME}] Bestehende Installation gefunden: ${SHARE_BASE}"
  tty_outln "Was soll ich tun?"
  tty_outln "  1) Vollständige Neu-Konfiguration (setzt Passwörter neu, richtet Dienste/Firewall/Samba/AP/PHP neu ein)"
  tty_outln "  2) Nur Webroot-Update (lädt/aktualisiert nur die Programme im Webroot; bestehende Dateien werden überschrieben)"
  while true; do
    tty_read "Auswahl [1/2]: " ans
    case "$ans" in
      1) echo "full"; return 0 ;;
      2) echo "webroot"; return 0 ;;
      *) tty_outln "Bitte 1 oder 2 eingeben." ;;
    esac
  done
}

ask_password_mode_tty() {
  local ans=""
  tty_outln ""
  tty_outln "Passwort-Optionen:"
  tty_outln "  1) Passwort selbst eingeben (keine Ausgabe; sinnvoll bei bestehenden Windows-Usern)"
  tty_outln "  2) Passwort generieren lassen (wird ausgegeben)"
  while true; do
    tty_read "Auswahl [1/2]: " ans
    case "$ans" in
      1) echo "manual"; return 0 ;;
      2) echo "gen"; return 0 ;;
      *) tty_outln "Bitte 1 oder 2 eingeben." ;;
    esac
  done
}

# -------------------------
# Trap: stty zurücksetzen
# -------------------------
cleanup_tty() {
  stty echo <"$TTY" >/dev/null 2>&1 || true
}
trap cleanup_tty EXIT INT TERM

# -------------------------
# Helper
# -------------------------
require_root() { [[ "${EUID}" -eq 0 ]] || die "Bitte als root ausführen: sudo bash fragebogenpi.sh"; }

rand_pw() {
  python3 - <<'PY'
import secrets
alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
print("".join(secrets.choice(alphabet) for _ in range(16)), end="")
PY
}

backup_file() { local f="$1"; [[ -f "$f" ]] && cp -a "$f" "${f}.bak.$(date +%Y%m%d_%H%M%S)"; }

get_iface_ipv4() { local i="$1"; ip -4 -o addr show dev "$i" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true; }
get_iface_mac()  { local i="$1"; cat "/sys/class/net/${i}/address" 2>/dev/null || true; }

systemd_unit_exists() { systemctl list-unit-files --type=service | awk '{print $1}' | grep -qx "$1"; }

port_in_use() { local port="$1"; ss -H -lntu 2>/dev/null | awk '{print $5}' | grep -Eq "(:|\\])${port}\$"; }

print_service_debug_and_die() {
  local svc="$1"
  warn "Service '${svc}' konnte nicht gestartet werden."
  warn "----- systemctl status ${svc} -----"
  systemctl --no-pager -l status "${svc}" || true
  warn "----- journalctl -xeu ${svc} (letzte 160 Zeilen) -----"
  journalctl --no-pager -xeu "${svc}" | tail -n 160 || true
  die "Abbruch, bitte Logausgabe oben prüfen."
}

ensure_linux_user_nologin() {
  local u="$1"
  if ! id -u "$u" >/dev/null 2>&1; then
    useradd -m -s /usr/sbin/nologin "$u"
  fi
}

ensure_system_admin_user() {
  local u="$1"
  local pw="$2"
  if id -u "$u" >/dev/null 2>&1; then
    usermod -aG sudo "$u" || true
    usermod -s /bin/bash "$u" || true
  else
    useradd -m -s /bin/bash "$u"
    usermod -aG sudo "$u" || true
  fi
  echo "${u}:${pw}" | chpasswd
}

normalize_relpath() {
  local p="$1"
  while [[ "$p" == ./* ]]; do p="${p#./}"; done
  echo "$p"
}

sanitize_relpath_or_die() {
  local p="$1"
  [[ -n "$p" ]] || die "Bootstrap-Liste enthält leeren Eintrag."
  [[ "$p" != /* ]] || die "Unsicherer Pfad in Bootstrap-Liste (absolut): '$p'"
  if echo "$p" | grep -Eq '(^|/)\.\.(/|$)'; then
    die "Unsicherer Pfad in Bootstrap-Liste (..): '$p'"
  fi
}

# Robust schreiben: via tee (umgeht heredoc->cat/TTY-Effekte)
write_file_tee() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  backup_file "$path"
  # Inhalt kommt über STDIN, Funktion erwartet bereits eine Heredoc-Weiterleitung beim Aufruf.
  tee "$path" >/dev/null
}

# -------------------------
# Pakete
# -------------------------
install_packages_full() {
  step "System aktualisieren und Pakete installieren"
  log "apt update/upgrade..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

  log "Installiere Pakete..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apache2 php libapache2-mod-php php-gd php-yaml \
    samba \
    hostapd dnsmasq \
    nftables \
    acl openssl \
    avahi-daemon \
    python3 \
    curl \
    unattended-upgrades
  ok "Pakete installiert"
}

install_packages_webroot_only() {
  step "Minimal: Tools für Webroot-Update sicherstellen"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl
  ok "curl ist verfügbar"
}

# -------------------------
# System Setup
# -------------------------
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
  step "Share-Verzeichnisse erstellen und Rechte setzen (${SHARE_BASE})"
  mkdir -p "$SHARE_GDT" "$SHARE_PDF"
  chown -R www-data:www-data "$SHARE_BASE"
  chmod -R 2775 "$SHARE_BASE"
  setfacl -R -m u:www-data:rwx "$SHARE_GDT" "$SHARE_PDF" || true
  setfacl -R -d -m u:www-data:rwx "$SHARE_GDT" "$SHARE_PDF" || true
  ok "Shares vorbereitet"
}

setup_webroot_perms() {
  step "Webroot Rechte setzen (${WEBROOT})"
  mkdir -p "$WEBROOT"
  chown -R www-data:www-data "$WEBROOT"
  chmod -R 2775 "$WEBROOT"
  setfacl -R -m u:www-data:rwx "$WEBROOT" || true
  setfacl -R -d -m u:www-data:rwx "$WEBROOT" || true
  ok "Webroot vorbereitet"
}

# -------------------------
# Samba
# -------------------------
setup_samba_base_config() {
  local smbconf="/etc/samba/smb.conf"
  write_file_tee "$smbconf" <<EOF
[global]
   workgroup = WORKGROUP
   server string = ${PROJECT_NAME} samba server
   security = user
   map to guest = Bad User
   guest account = nobody

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
}

append_samba_shares_anonymous() {
  local smbconf="/etc/samba/smb.conf"
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
}

append_samba_shares_auth() {
  local smbconf="/etc/samba/smb.conf"
  local userlist="$1"
  cat >> "$smbconf" <<EOF

[GDT]
   path = ${SHARE_GDT}
   browseable = yes
   read only = no
   guest ok = no
   valid users = ${userlist}
   force user = www-data
   force group = www-data

[PDF]
   path = ${SHARE_PDF}
   browseable = yes
   read only = no
   guest ok = no
   valid users = ${userlist}
   force user = www-data
   force group = www-data
EOF
}

append_samba_webroot_share_admin_only() {
  local smbconf="/etc/samba/smb.conf"
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
}

append_samba_webroot_share_guest() {
  local smbconf="/etc/samba/smb.conf"
  cat >> "$smbconf" <<EOF

[WEBROOT]
   path = ${WEBROOT}
   browseable = yes
   read only = no
   guest ok = yes
   force user = www-data
   force group = www-data
EOF
}

restart_samba() {
  systemctl enable --now smbd nmbd >/dev/null 2>&1 || true
  systemctl restart smbd nmbd >/dev/null 2>&1 || true
}

set_samba_password() {
  local user="$1"
  local pw="$2"
  (echo "$pw"; echo "$pw") | smbpasswd -a -s "$user"
  smbpasswd -e "$user" >/dev/null 2>&1 || true
}

# -------------------------
# WLAN/AP
# -------------------------
configure_nm_unmanage_wlan0() {
  if command -v nmcli >/dev/null 2>&1 && systemctl is-active NetworkManager >/dev/null 2>&1; then
    log "NetworkManager erkannt – setze ${AP_INTERFACE} auf unmanaged..."
    local nmconf="/etc/NetworkManager/conf.d/99-fragebogenpi-unmanage-${AP_INTERFACE}.conf"
    write_file_tee "$nmconf" <<EOF
[keyfile]
unmanaged-devices=interface-name:${AP_INTERFACE}
EOF
    systemctl reload NetworkManager >/dev/null 2>&1 || systemctl restart NetworkManager >/dev/null 2>&1 || true
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

command -v rfkill >/dev/null 2>&1 && rfkill unblock wifi || true

for i in {1..20}; do
  [[ -d "/sys/class/net/\${AP_INTERFACE}" ]] && break
  sleep 0.2
done

[[ -d "/sys/class/net/\${AP_INTERFACE}" ]] || exit 1

/usr/sbin/ip link set dev "\${AP_INTERFACE}" up
/usr/sbin/ip -4 addr flush dev "\${AP_INTERFACE}" || true
/usr/sbin/ip addr add "\${AP_IP}/24" dev "\${AP_INTERFACE}"

GOT_IP="\$(/usr/sbin/ip -4 -o addr show dev "\${AP_INTERFACE}" | awk '{print \$4}' | cut -d/ -f1 | head -n1 || true)"
[[ "\${GOT_IP:-}" == "\${AP_IP}" ]] || exit 1
EOF
  chmod 0755 "$AP_IP_HELPER"
}

install_ap_ip_service() {
  install_ap_ip_helper
  write_file_tee "$AP_IP_SERVICE" <<EOF
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
  systemctl enable --now fragebogenpi-ap-ip.service >/dev/null 2>&1 || true
  systemctl restart fragebogenpi-ap-ip.service >/dev/null 2>&1 || print_service_debug_and_die "fragebogenpi-ap-ip.service"
}

configure_ap_ip() {
  step "WLAN-AP IP auf ${AP_INTERFACE} setzen (${AP_IP}/24)"
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
    systemctl restart dhcpcd >/dev/null 2>&1 || true
  else
    log "dhcpcd nicht vorhanden – nutze systemd oneshot (iproute2)."
    install_ap_ip_service
  fi

  ip link set dev "${AP_INTERFACE}" up >/dev/null 2>&1 || true
  ip addr add "${AP_IP}/24" dev "${AP_INTERFACE}" >/dev/null 2>&1 || true

  local got_ip
  got_ip="$(get_iface_ipv4 "${AP_INTERFACE}")"
  [[ "${got_ip:-}" == "$AP_IP" ]] || die "AP-IP konnte nicht gesetzt werden; ${AP_INTERFACE} hat '${got_ip:-<leer>}' statt '${AP_IP}'."
  ok "AP-IP gesetzt"
}

setup_ap_hostapd_dnsmasq() {
  step "WLAN Access Point (hostapd) + DHCP (dnsmasq) konfigurieren"
  local wifi_pw="$1"

  write_file_tee "/etc/hostapd/hostapd.conf" <<EOF
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

  backup_file "/etc/default/hostapd"
  sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd || true

  local dnsconf="/etc/dnsmasq.d/fragebogenpi.conf"
  if port_in_use 53; then
    warn "Port 53 belegt -> dnsmasq DHCP-only."
    write_file_tee "$dnsconf" <<EOF
interface=${AP_INTERFACE}
bind-interfaces
listen-address=${AP_IP}
port=0
dhcp-range=${AP_DHCP_START},${AP_DHCP_END},${AP_NETMASK},12h
EOF
  else
    write_file_tee "$dnsconf" <<EOF
interface=${AP_INTERFACE}
bind-interfaces
listen-address=${AP_IP}
dhcp-range=${AP_DHCP_START},${AP_DHCP_END},${AP_NETMASK},12h
address=/#/${AP_IP}
EOF
  fi

  systemctl enable --now dnsmasq >/dev/null 2>&1 || true
  systemctl restart dnsmasq >/dev/null 2>&1 || print_service_debug_and_die "dnsmasq.service"

  systemctl unmask hostapd >/dev/null 2>&1 || true
  systemctl enable --now hostapd >/dev/null 2>&1 || true
  systemctl restart hostapd >/dev/null 2>&1 || print_service_debug_and_die "hostapd.service"

  ok "AP/DHCP aktiv"
}

setup_https_if_requested() {
  step "Webserver konfigurieren (HTTP/HTTPS)"
  local mode="$1"
  if [[ "$mode" == "http" ]]; then
    ok "HTTP-only"
    return 0
  fi

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
    -subj "/C=DE/ST=DE/L=DE/O=fragebogenpi/OU=fragebogenpi/CN=${HOSTNAME_FQDN}.local" >/dev/null 2>&1

  chmod 600 "$SSL_KEY"
  chmod 644 "$SSL_CRT"

  a2enmod ssl >/dev/null 2>&1
  a2enmod rewrite >/dev/null 2>&1

  local ssl_site="/etc/apache2/sites-available/default-ssl.conf"
  backup_file "$ssl_site"
  sed -i "s|^\s*SSLCertificateFile\s\+.*|SSLCertificateFile ${SSL_CRT}|g" "$ssl_site"
  sed -i "s|^\s*SSLCertificateKeyFile\s\+.*|SSLCertificateKeyFile ${SSL_KEY}|g" "$ssl_site"

  a2ensite default-ssl >/dev/null 2>&1
  systemctl reload apache2 >/dev/null 2>&1 || true
  ok "HTTPS aktiv (self-signed bis 2050)"
}

# -------------------------
# Firewall (erst am Ende aktivieren)
# -------------------------
write_firewall_config_only() {
  step "Firewall-Konfiguration schreiben (Aktivierung erfolgt erst ganz am Ende)"
  write_file_tee "/etc/nftables.conf" <<EOF
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

  write_file_tee "/etc/sysctl.d/99-fragebogenpi.conf" <<EOF
net.ipv4.ip_forward=0
net.ipv6.conf.all.forwarding=0
EOF

  ok "Firewall-Konfiguration geschrieben"
}

activate_firewall_now() {
  step "Firewall aktivieren (WLAN wird ab jetzt streng gefiltert)"
  sysctl --system >/dev/null 2>&1 || true
  systemctl enable --now nftables >/dev/null 2>&1 || true
  systemctl restart nftables >/dev/null 2>&1 || true
  ok "Firewall aktiv"
}

ensure_sshd_normal_listen() {
  step "SSH: sshd soll normal auf allen Interfaces lauschen (Firewall blockt WLAN)"
  local sshd_conf="/etc/ssh/sshd_config"
  if [[ -f "$sshd_conf" ]]; then
    backup_file "$sshd_conf"
    sed -i '/^\s*ListenAddress\s\+/d' "$sshd_conf"
  fi
  ok "sshd_config bereinigt (Restart/Reboot später)"
}

# -------------------------
# PHP / Updates / Bootstrap
# -------------------------
configure_php_settings() {
  step "PHP Optionen setzen (Upload/Timeouts)"
  local php_ver
  php_ver="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
  local apache_conf_dir="/etc/php/${php_ver}/apache2/conf.d"
  local cli_conf_dir="/etc/php/${php_ver}/cli/conf.d"
  local ini_name="99-fragebogenpi.ini"

  mkdir -p "$apache_conf_dir" "$cli_conf_dir"
  local path="${apache_conf_dir}/${ini_name}"
  write_file_tee "$path" <<EOF
; ${PROJECT_NAME} custom PHP settings
upload_max_filesize = ${PHP_UPLOAD_MAX}
post_max_size = ${PHP_POST_MAX}
max_file_uploads = ${PHP_MAX_UPLOADS}
max_execution_time = ${PHP_MAX_EXEC}
max_input_time = ${PHP_MAX_INPUT}
EOF
  cp -a "$path" "${cli_conf_dir}/${ini_name}"
  systemctl reload apache2 >/dev/null 2>&1 || true
  ok "PHP Settings gesetzt"
}

enable_auto_updates() {
  step "Auto-Update aktivieren (unattended-upgrades)"
  write_file_tee "/etc/apt/apt.conf.d/20auto-upgrades" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
  systemctl enable unattended-upgrades >/dev/null 2>&1 || true
  systemctl start unattended-upgrades >/dev/null 2>&1 || true
  systemctl enable apt-daily.timer >/dev/null 2>&1 || true
  systemctl enable apt-daily-upgrade.timer >/dev/null 2>&1 || true
  ok "Auto-Updates aktiv"
}

download_bootstrap_files_to_webroot() {
  step "Webroot Bootstrap: Dateiliste laden und Dateien herunterladen"
  command -v curl >/dev/null 2>&1 || { apt-get update -y; DEBIAN_FRONTEND=noninteractive apt-get install -y curl; }

  local base_url
  base_url="$(echo "$BOOTSTRAP_URL" | sed 's#^\(.*\)/[^/]*$#\1#')"

  local tmp_list
  tmp_list="$(mktemp)"
  trap 'rm -f "$tmp_list"' EXIT

  log "Lade Bootstrap-Liste: ${BOOTSTRAP_URL}"
  curl -fsSL "$BOOTSTRAP_URL" -o "$tmp_list" || die "Download fehlgeschlagen: bootstrap"

  local count_ok=0 count_skip=0
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    local line
    line="$(echo "$raw" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"
    if [[ -z "$line" ]] || [[ "$line" == \#* ]]; then
      count_skip=$((count_skip+1))
      continue
    fi
    line="$(normalize_relpath "$line")"
    sanitize_relpath_or_die "$line"

    local url="${base_url}/${line}"
    local dst="${WEBROOT}/${line}"
    mkdir -p "$(dirname "$dst")"
    log "Download: ${line}"
    curl -fsSL "$url" -o "$dst" || die "Download fehlgeschlagen: ${url}"
    chown www-data:www-data "$dst" || true
    chmod 0644 "$dst" || true
    count_ok=$((count_ok+1))
  done < "$tmp_list"

  ok "Bootstrap: ${count_ok} Datei(en) geladen (skip: ${count_skip})"
}

# -------------------------
# Credentials file (optional)
# -------------------------
write_credentials_file_if_requested() {
  local want="$1"
  local web_mode="$2"
  local protect_shares="$3"
  local wifi_pw="$4"
  local default_smb_pw_display="$5"
  local admin_pw_display="$6"
  local lan_ip="$7"
  local lan_mac="$8"
  local ap_mac="$9"
  shift 9
  local smb_users_block="${*:-}"

  [[ "$want" == "yes" ]] || { log "Zugangsdaten-Datei: nicht gewünscht."; return 0; }

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
    echo "Projekt: ${PROJECT_NAME}"
    echo "Version: ${VERSION}"
    echo "Hostname: ${HOSTNAME_FQDN}"
    echo
    echo "LAN IP (aktuell): ${lan_ip:-<unbekannt>}"
    echo "LAN MAC (eth0):   ${lan_mac:-<unbekannt>}"
    echo "WLAN MAC (wlan0): ${ap_mac:-<unbekannt>}"
    echo
    echo "WLAN SSID: ${AP_SSID}"
    echo "WLAN Passwort: ${wifi_pw}"
    echo "WLAN IP (Pi): ${AP_IP}"
    echo "Webserver (WLAN): http://${AP_IP}/"
    [[ "$web_mode" == "https" ]] && echo "Webserver (WLAN): https://${AP_IP}/ (self-signed)"
    echo
    echo "Samba Shares (LAN):"
    echo "\\\\<LAN-IP>\\GDT -> ${SHARE_GDT}"
    echo "\\\\<LAN-IP>\\PDF -> ${SHARE_PDF}"
    echo "\\\\<LAN-IP>\\WEBROOT -> ${WEBROOT}"
    echo
    if [[ "$protect_shares" == "yes" ]]; then
      echo "Default Samba User (GDT/PDF): ${DEFAULT_SAMBA_USER}"
      echo "Default Samba Passwort: ${default_smb_pw_display:-manuell gesetzt (keine Ausgabe)}"
    else
      echo "GDT/PDF Zugriff: anonym (guest), schreibbar"
    fi
    echo
    echo "Admin (SSH + sudo): ${ADMIN_USER}"
    echo "Admin Passwort: ${admin_pw_display:-manuell gesetzt (keine Ausgabe)}"
    echo
    echo "SMB-User Übersicht:"
    echo "${smb_users_block:-<keine>}"
    echo
    echo "Bootstrap Quelle: ${BOOTSTRAP_URL}"
    echo
    echo "PHP Optionen:"
    echo "upload_max_filesize=${PHP_UPLOAD_MAX}"
    echo "post_max_size=${PHP_POST_MAX}"
    echo "max_file_uploads=${PHP_MAX_UPLOADS}"
    echo "max_execution_time=${PHP_MAX_EXEC}"
    echo "max_input_time=${PHP_MAX_INPUT}"
    echo
    echo "Auto-Update: unattended-upgrades aktiv"
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
# Samba Users loop
# -------------------------
SMB_USERS_BLOCK=""

append_smb_user_line() {
  local u="$1"
  local p="$2"
  SMB_USERS_BLOCK+=$(printf "User: %-20s Passwort: %s\n" "$u" "$p")
}

create_samba_users_loop() {
  step "Samba-Benutzer anlegen (optional)"
  if ! ask_yes_no_tty "Sollen weitere Samba-Benutzer angelegt werden?" "n"; then
    log "Keine zusätzlichen Samba-Benutzer angelegt."
    return 0
  fi

  while true; do
    local u=""
    tty_read "Samba-Benutzername: " u
    u="$(echo "$u" | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//')"
    [[ -n "$u" ]] || { tty_outln "Bitte einen Namen eingeben."; continue; }

    ensure_linux_user_nologin "$u"

    local mode pw pw2 display
    mode="$(ask_password_mode_tty)"
    if [[ "$mode" == "manual" ]]; then
      tty_outln "Hinweis: Anonymer Zugriff kann in Windows/Gruppenrichtlinien blockiert sein."
      tty_outln "Manuelles Passwort ist oft sinnvoll, wenn es identisch zum Windows-Login sein soll."
      tty_read_silent "Passwort für '${u}': " pw
      tty_read_silent "Passwort wiederholen: " pw2
      [[ "$pw" == "$pw2" ]] || { tty_outln "Passwörter stimmen nicht überein."; continue; }
      set_samba_password "$u" "$pw"
      display="(manuell, keine Ausgabe)"
    else
      pw="$(rand_pw)"
      set_samba_password "$u" "$pw"
      display="$pw"
    fi

    append_smb_user_line "$u" "$display"
    tty_outln "[OK] Samba-Benutzer angelegt: $u"

    if ! ask_yes_no_tty "Noch einen Samba-Benutzer anlegen?" "n"; then
      break
    fi
  done
}

# -------------------------
# Delete User prompt
# -------------------------
maybe_delete_existing_user() {
  echo
  if ! ask_yes_no_tty "Soll ein bestehender Systembenutzer gelöscht werden?" "n"; then
    log "Kein Benutzer gelöscht."
    return 0
  fi

  local u=""
  tty_read "Benutzername (Default: pi): " u
  u="${u:-pi}"

  if [[ "$u" == "root" ]]; then
    warn "root wird nicht gelöscht."
    return 0
  fi
  if ! id -u "$u" >/dev/null 2>&1; then
    warn "Benutzer '${u}' existiert nicht."
    return 0
  fi

  step "Lösche Benutzer '${u}' (inkl. Home-Verzeichnis)"
  smbpasswd -x "$u" >/dev/null 2>&1 || true
  userdel -r "$u" >/dev/null 2>&1 || true
  ok "Benutzer '${u}' gelöscht (soweit möglich)."
}

# -------------------------
# MAIN
# -------------------------
main() {
  require_root
  banner
  log "Starte Setup '${PROJECT_NAME}' (v${VERSION})..."

  [[ -d /sys/class/net/${AP_INTERFACE} ]] || die "Interface ${AP_INTERFACE} nicht gefunden."
  if [[ ! -d /sys/class/net/${LAN_INTERFACE} ]]; then
    warn "Interface ${LAN_INTERFACE} nicht gefunden (LAN). Samba bind gilt dann evtl. nicht."
  fi

  # Erste Frage: vorhandene Installation?
  local mode="full"
  if [[ -d "${SHARE_BASE}" ]]; then
    mode="$(ask_choice_existing_install_tty)"
  fi

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

  step "Konfiguration abfragen"

  # Admin-Passwort
  local admin_pw_mode admin_pw admin_pw_display
  tty_outln ""
  tty_outln "Admin-User '${ADMIN_USER}' (SSH-Login + sudo) wird angelegt."
  admin_pw_mode="$(ask_password_mode_tty)"
  if [[ "$admin_pw_mode" == "manual" ]]; then
    tty_read_silent "Passwort für '${ADMIN_USER}': " admin_pw
    tty_read_silent "Passwort wiederholen: " admin_pw2
    [[ "$admin_pw" == "$admin_pw2" ]] || die "Admin-Passwörter stimmen nicht überein."
    admin_pw_display="(manuell, keine Ausgabe)"
  else
    admin_pw="$(rand_pw)"
    admin_pw_display="$admin_pw"
  fi

  local wifi_pw web_mode protect_shares default_smb_pw_mode default_smb_pw default_smb_pw_display
  wifi_pw="$(rand_pw)"
  web_mode="$(ask_choice_http_https_tty)"

  tty_outln ""
  tty_outln "Hinweis: Anonymer Samba-Zugriff (Guest) kann je nach Windows/Gruppenrichtlinien blockiert sein."
  tty_outln "Wenn Windows zickt: besser Benutzer anlegen (ggf. Passwort identisch zum Windows-Login)."

  protect_shares="no"
  default_smb_pw_display=""
  if ask_yes_no_tty "Samba-Shares GDT/PDF mit Passwort schützen?" "y"; then
    protect_shares="yes"
    ensure_linux_user_nologin "${DEFAULT_SAMBA_USER}"

    default_smb_pw_mode="$(ask_password_mode_tty)"
    if [[ "$default_smb_pw_mode" == "manual" ]]; then
      tty_read_silent "Passwort für '${DEFAULT_SAMBA_USER}': " default_smb_pw
      tty_read_silent "Passwort wiederholen: " default_smb_pw2
      [[ "$default_smb_pw" == "$default_smb_pw2" ]] || die "Passwörter stimmen nicht überein."
      default_smb_pw_display="(manuell, keine Ausgabe)"
    else
      default_smb_pw="$(rand_pw)"
      default_smb_pw_display="$default_smb_pw"
    fi
  fi

  # WEBROOT Share für alle per Samba?
  local webroot_guest="no"
  if ask_yes_no_tty "Soll das Samba-Share WEBROOT für alle (Gast) schreibbar sein? (nicht empfohlen)" "n"; then
    webroot_guest="yes"
  fi

  # Zugangsdaten-Datei?
  local save_creds="no"
  if ask_yes_no_tty "Zugangsdaten zusätzlich als Datei ins PDF-Share schreiben (BITTE danach löschen)?" "n"; then
    save_creds="yes"
  fi

  ok "Eingaben übernommen"

  install_packages_full
  set_hostname
  setup_share_dirs
  setup_webroot_perms

  step "Admin-User anlegen (SSH + sudo)"
  ensure_system_admin_user "${ADMIN_USER}" "${admin_pw}"
  set_samba_password "${ADMIN_USER}" "${admin_pw}" >/dev/null 2>&1 || true
  append_smb_user_line "${ADMIN_USER}" "${admin_pw_display}"
  ok "Admin '${ADMIN_USER}' angelegt"

  step "Samba konfigurieren"
  setup_samba_base_config

  if [[ "$protect_shares" == "yes" ]]; then
    set_samba_password "${DEFAULT_SAMBA_USER}" "${default_smb_pw}"
    append_samba_shares_auth "${DEFAULT_SAMBA_USER}"
    append_smb_user_line "${DEFAULT_SAMBA_USER}" "${default_smb_pw_display}"
  else
    append_samba_shares_anonymous
  fi

  if [[ "$webroot_guest" == "yes" ]]; then
    append_samba_webroot_share_guest
  else
    append_samba_webroot_share_admin_only
  fi

  restart_samba
  ok "Samba läuft (nur LAN/${LAN_INTERFACE})"

  configure_ap_ip
  setup_ap_hostapd_dnsmasq "$wifi_pw"
  setup_https_if_requested "$web_mode"

  ensure_sshd_normal_listen
  configure_php_settings
  download_bootstrap_files_to_webroot
  enable_auto_updates

  write_firewall_config_only

  create_samba_users_loop
  restart_samba

  # Abschlussdaten
  local lan_ip lan_mac ap_mac
  lan_ip="$(get_iface_ipv4 "${LAN_INTERFACE}")"
  lan_mac="$(get_iface_mac "${LAN_INTERFACE}")"
  ap_mac="$(get_iface_mac "${AP_INTERFACE}")"

  write_credentials_file_if_requested \
    "$save_creds" "$web_mode" "$protect_shares" "$wifi_pw" "$default_smb_pw_display" "$admin_pw_display" \
    "$lan_ip" "$lan_mac" "$ap_mac" \
    "$SMB_USERS_BLOCK"

  step "Abschlussinformationen"
  echo
  echo "==================== ZUGANGSDATEN ===================="
  echo "Projekt:               ${PROJECT_NAME}"
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
  [[ "$web_mode" == "https" ]] && echo "Webserver (WLAN): https://${AP_IP}/  (self-signed Warnung ist normal)"
  echo
  echo "LAN IP (aktuell): ${lan_ip:-<unbekannt>}"
  echo "LAN MAC (eth0):   ${lan_mac:-<unbekannt>}"
  echo "WLAN MAC (wlan0): ${ap_mac:-<unbekannt>}"
  echo
  echo "WICHTIG:"
  echo "  Im Router sollte für '${HOSTNAME_FQDN}' eine feste IP / DHCP-Reservation gesetzt werden."
  echo "  Nutze dafür die LAN MAC-Adresse (eth0) von oben."
  echo
  echo "Samba Shares (nur LAN/${LAN_INTERFACE}, nicht WLAN):"
  echo "  \\\\<LAN-IP-des-Pi>\\GDT      -> ${SHARE_GDT}"
  echo "  \\\\<LAN-IP-des-Pi>\\PDF      -> ${SHARE_PDF}"
  echo "  \\\\<LAN-IP-des-Pi>\\WEBROOT  -> ${WEBROOT}"
  echo
  echo "WEBROOT Share:"
  if [[ "$webroot_guest" == "yes" ]]; then
    echo "  -> für alle im LAN als Gast schreibbar (nicht empfohlen)"
  else
    echo "  -> nur '${ADMIN_USER}' (empfohlen)"
  fi
  echo
  echo "SMB-User (Passwörter ggf. manuell gesetzt -> keine Ausgabe):"
  echo "-------------------------------------------------------"
  echo -n "$SMB_USERS_BLOCK"
  echo "-------------------------------------------------------"
  echo
  echo "Admin (SSH + sudo): ${ADMIN_USER}"
  echo "Admin Passwort:     ${admin_pw_display}"
  echo
  echo "Bootstrap:"
  echo "  Quelle: ${BOOTSTRAP_URL}"
  echo "  Ziel:   ${WEBROOT}"
  echo
  echo "PHP Pakete: php-gd, php-yaml"
  echo "PHP Optionen:"
  echo "  upload_max_filesize=${PHP_UPLOAD_MAX}"
  echo "  post_max_size=${PHP_POST_MAX}"
  echo "  max_file_uploads=${PHP_MAX_UPLOADS}"
  echo "  max_execution_time=${PHP_MAX_EXEC}"
  echo "  max_input_time=${PHP_MAX_INPUT}"
  echo
  echo "Auto-Update: unattended-upgrades aktiv"
  if [[ "$save_creds" == "yes" ]]; then
    echo
    echo "Zugangsdaten-Datei:"
    echo "  ${CRED_FILE}"
    echo "  (BITTE NACH ÜBERNAHME LÖSCHEN!)"
  fi
  echo "======================================================"
  echo

  maybe_delete_existing_user
  activate_firewall_now

  step "Reboot"
  log "System wird jetzt neu gestartet..."
  systemctl reboot
}

main "$@"
