#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# fragebogenpi wartezimmerbildschirm — Installer
# Version: 1.5.3
# Stand:   2026-07-18
# Autor:   Dr. Thomas Kienzle
#
# Changelog (komplett, ab 1.0):
# - 1.0:
#   - Basis: Desktop + Kiosk-Browser + Apache/PHP + Samba + Backend + JSON-Konfig.
# - 1.1:
#   - Webroot /var/www/html (kein Unterverzeichnis), Startseite wartezimmer.php.
#   - Samba Guest RW + setgid-Rechte, Fetch aktiviert (localhost), Löschskript.
# - 1.2:
#   - Footer eingeblendet (später nur bei Meldung gewünscht), Hostname/WLAN-Abfragen ergänzt,
#     Logging wieder deaktiviert, Boot-Refresh-Fix per simplem wait-loop vorbereitet.
# - 1.3:
#   - Boot-Playback-Fix “perfekt” (ohne Alt-Tab/F5):
#     - Kiosk-Robustheit: wartet auf lokale Endpunkte (PHP+JSON+Playlist),
#       deaktiviert DPMS/Screensaver, setzt Anti-Background-Throttling-Flags,
#       bringt Chromium per wmctrl in Vordergrund und triggert einmaliges Reload per xdotool.
#     - Web-App Self-Heal: skip invalid videos (onerror), Watchdog-Retry, focus/visibility retry,
#       Retry wenn Playlist leer.
#   - Dotfiles/AppleDouble werden nicht mehr gelistet (._* und .* werden gefiltert).
#   - Footer erscheint NUR während der Aufruf-Meldung (Overlay).
#   - Hostname-Abfrage + robustes Setzen (Default: "wartezimmer") inkl. Verifikation.
#   - WLAN: erst Abfrage "WLAN aktivieren?" → nur dann SSID/Passwort (Default SSID: "fragebogenpi").
#   - Firewall via nftables wieder aktiv:
#     - wlan0 inbound dicht (nur established/related, DHCP, Ping)
#     - eth0 vollständig offen (keine Einschränkungen im LAN)
#   - Audio-Konfig in wartezimmer.json.
#   - Backend: parst ausschließlich 3102 (Vorname) + 3101 (Nachname) aus GDT.
# - 1.4:
#   - Feature-Nachbau aller Erweiterungen seit 1.3 (bis inkl. 1.3.5), konservativ auf 1.3-Basis:
#     - Hostname zusätzlich in /boot/firmware/user-data (cloud-init) patchen: ganze "hostname:"-Zeile ersetzen (idempotent).
#     - wartezimmer.json: display_seconds=10; rooms=sprechzimmer1+2; gültige _comment0.._comment3 Hinweise.
#     - Webroot: loesche-sprechzimmer2.php ergänzt; README erweitert inkl. Sicherheitssatz.
#     - Audio: default_sound=jsbach.m4a; Sound-Bootstrap; list_media.php listet mp3+m4a.
#     - Backend: optionales Name-Abkürzen per name_format (Zählen ohne Leerzeichen/Bindestriche).
#     - Frontend: Chime robust; während Meldung Video-Audio ducken und danach restore.
# - 1.5.0:
#   - Browser im Kiosk auf Firefox umgestellt (konservativ, restliche Architektur unverändert).
#   - Beispielvideo wird gebootstrapped nach /var/www/html/videos/zzz_beispielvideo.mp4 (fail-fast, retries, atomar; nur wenn fehlend).
# - 1.5.1:
#   - Versuch: Firefox-Kioskprofil per Script im Autostart sicherstellen (Prepare-Script), zeigte in der Praxis noch Profilmanager.
# - 1.5.2:
#   - Firefox-Kiosk-Startpfad im Openbox-Autostart exakt nach dem praxiserprobten Ablauf:
#     - firefox -CreateProfile kiosk
#     - profiles.ini parsen (INI="$HOME_DIR/.mozilla/firefox/profiles.ini")
#     - user.js schreiben, permissions/content-prefs reset
#     - dann firefox -P kiosk --kiosk --no-remote http://127.0.0.1/wartezimmer.php
#     - Umsetzung sauber als Script ohne sudo/EOF/echo.
#   - Installer: am Ende Abfrage „Reboot jetzt?“ und bei Bestätigung reboot.
# - 1.5.3:
#   - Wartezimmer-Aufrufe werden nur noch über eine einzelne fragebogenpi-Server-URL abgefragt.
#   - Der Wartezimmer-Pi erhält keine rohe GDT-Datei mehr, sondern nur Anzeigetext und Ziel.
#   - Installer fragt SSID, WLAN-Passwort, fragebogenpi-IP und Query-Intervall interaktiv ab.
#   - NetworkManager wird bevorzugt verwendet; wpa_supplicant bleibt als Fallback erhalten.
#   - Alte direkte GDT- und Lösch-URLs sowie die zugehörigen Hilfsdateien wurden entfernt.
#   - Wartezimmerbezogenes Logging wurde vollständig entfernt/deaktiviert.
# ==============================================================================

APP_NAME="fragebogenpi wartezimmerbildschirm"
VERSION="1.5.3"

WEBROOT_DIR="/var/www/html"
CONFIG_JSON="${WEBROOT_DIR}/wartezimmer.json"
SERVER_CONFIG_DIR="/etc/fragebogenpi-wartezimmer"
SERVER_CONFIG_JSON="${SERVER_CONFIG_DIR}/server.json"

WLAN_SSID="fragebogenpi"
FRAGEBOGENPI_SERVER_IP="10.23.0.1"
QUERY_INTERVAL_SECONDS="3"

INFODISPLAY_USER="infodisplay"
INFODISPLAY_GROUP="infodisplay"

# Kiosk user (Autologin)
KIOSK_USER="pi"
KIOSK_HOME="/home/${KIOSK_USER}"

# Bootstrap assets
JSBACH_URL="https://github.com/thomaskien/fragebogenpi/raw/refs/heads/main/jsbach.m4a"
JSBACH_DEST="${WEBROOT_DIR}/sounds/jsbach.m4a"

EXAMPLEVIDEO_URL="https://github.com/thomaskien/fragebogenpi/raw/refs/heads/main/zzz_beispielvideo.mp4"
EXAMPLEVIDEO_DEST="${WEBROOT_DIR}/videos/zzz_beispielvideo.mp4"

say() { echo -e "\n### $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Bitte als root ausführen."
  fi
}

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    cp -a "$f" "${f}.old.${ts}"
  fi
}

ensure_group() {
  local g="$1"
  if ! getent group "$g" >/dev/null 2>&1; then
    groupadd "$g"
  fi
}

ensure_user_infodisplay() {
  if id "$INFODISPLAY_USER" >/dev/null 2>&1; then
    return 0
  fi
  say "Lege Benutzer an: ${INFODISPLAY_USER}"
  useradd -r -m -d "/var/lib/${INFODISPLAY_USER}" -s /usr/sbin/nologin -g "${INFODISPLAY_GROUP}" "${INFODISPLAY_USER}"
}

ensure_kiosk_user() {
  if id "$KIOSK_USER" >/dev/null 2>&1; then
    return 0
  fi
  say "Benutzer '${KIOSK_USER}' nicht gefunden — lege an (Autologin-Kiosk)."
  useradd -m -d "$KIOSK_HOME" -s /bin/bash -G sudo,audio,video,input,render,netdev "$KIOSK_USER"
  passwd -d "$KIOSK_USER" >/dev/null 2>&1 || true
}

apt_install() {
  say "APT: update + upgrade"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get upgrade -y

  say "APT: install Pakete"
  apt-get install -y \
    ca-certificates curl wget jq \
    apache2 libapache2-mod-php php php-cli \
    samba \
    nftables \
    wpasupplicant wireless-tools \
    xserver-xorg xinit x11-xserver-utils \
    lightdm openbox \
    firefox-esr \
    unclutter-xfixes \
    wmctrl xdotool \
    python3 python3-aiohttp python3-requests
}

patch_cloud_init_user_data_hostname() {
  local hn="$1"
  local f="/boot/firmware/user-data"

  [[ -f "$f" ]] || return 0
  grep -qE '^\s*hostname\s*:' "$f" || return 0

  say "cloud-init: Patche ${f} (hostname: Zeile)"
  backup_file "$f"

  local tmp
  tmp="$(mktemp)"

  python3 - "$hn" "$f" "$tmp" <<'PY'
import re, sys
hn = sys.argv[1]
src = sys.argv[2]
dst = sys.argv[3]
with open(src, "r", encoding="utf-8", errors="replace") as fp:
    data = fp.read()
pat = re.compile(r'^(\s*hostname\s*:\s*).*$',
                 re.MULTILINE)
new, n = pat.subn(lambda m: m.group(1) + hn, data, count=1)
if n == 0:
    new = data
with open(dst, "w", encoding="utf-8") as fp:
    fp.write(new)
PY

  mv -f "$tmp" "$f"
}

ask_hostname_and_set_robust() {
  say "Hostname setzen (robust)"
  local hn
  read -r -p "Hostname [default: wartezimmer]: " hn
  hn="${hn:-wartezimmer}"

  if [[ ! "$hn" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]]; then
    die "Ungültiger Hostname: '$hn' (erlaubt: a-z A-Z 0-9 - , max 63 Zeichen, nicht mit - starten)."
  fi

  say "Setze Hostname auf: $hn"

  echo "$hn" >/etc/hostname

  backup_file /etc/hosts
  if grep -qE '^127\.0\.1\.1' /etc/hosts; then
    sed -i -E "s/^127\.0\.1\.1\s+.*/127.0.1.1\t${hn}/" /etc/hosts
  else
    echo -e "127.0.1.1\t${hn}" >>/etc/hosts
  fi

  hostname "$hn" || true

  if command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "$hn" || true
  fi

  patch_cloud_init_user_data_hostname "$hn" || true

  local cur
  cur="$(hostname || true)"
  if [[ "$cur" != "$hn" ]]; then
    die "Hostname konnte nicht gesetzt werden (ist '$cur', erwartet '$hn')."
  fi
}

ask_wlan_enable_and_configure() {
  say "WLAN optional konfigurieren"
  local ans
  read -r -p "WLAN aktivieren und konfigurieren? [Y/n]: " ans
  ans="${ans:-Y}"
  if [[ "$ans" =~ ^([nN]|no|NO)$ ]]; then
    say "WLAN-Konfiguration übersprungen."
    return 1
  fi

  local ssid pass1 pass2
  read -r -p "WLAN SSID [${WLAN_SSID}]: " ssid
  WLAN_SSID="${ssid:-$WLAN_SSID}"

  while true; do
    read -r -s -p "WLAN Passwort (WPA2/PSK): " pass1 >&2
    printf '\n' >&2
    read -r -s -p "WLAN Passwort (Wiederholung): " pass2 >&2
    printf '\n' >&2
    [[ -n "$pass1" ]] || { echo "Passwort darf nicht leer sein." >&2; continue; }
    [[ "$pass1" == "$pass2" ]] || { echo "Passwörter stimmen nicht überein." >&2; continue; }
    break
  done

  [[ -n "$WLAN_SSID" ]] || die "SSID leer."
  (( ${#WLAN_SSID} <= 32 )) || die "SSID ist länger als 32 Zeichen."

  if command -v nmcli >/dev/null 2>&1 && systemctl is-active NetworkManager >/dev/null 2>&1; then
    say "Konfiguriere WLAN über NetworkManager"
    local connection_name="wartezimmer-wlan"
    if nmcli -t -f NAME connection show | grep -Fxq "$connection_name"; then
      nmcli connection modify "$connection_name" 802-11-wireless.ssid "$WLAN_SSID"
    else
      nmcli connection add type wifi ifname wlan0 con-name "$connection_name" ssid "$WLAN_SSID"
    fi
    nmcli connection modify "$connection_name" \
      connection.autoconnect yes \
      802-11-wireless.mode infrastructure \
      802-11-wireless-security.key-mgmt wpa-psk \
      802-11-wireless-security.psk "$pass1" \
      ipv4.method auto \
      ipv6.method auto
    nmcli connection up "$connection_name" >/dev/null || die "WLAN-Verbindung über NetworkManager fehlgeschlagen."
    return 0
  fi

  say "NetworkManager nicht aktiv – verwende wpa_supplicant (country=DE)"
  backup_file /etc/wpa_supplicant/wpa_supplicant.conf

  local tmp
  tmp="$(mktemp)"
  wpa_passphrase "$WLAN_SSID" "$pass1" | sed '/^[[:space:]]*#psk=/d' >"$tmp"

  cat >/etc/wpa_supplicant/wpa_supplicant.conf <<EOF
country=DE
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

$(cat "$tmp")
EOF
  rm -f "$tmp"
  chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf

  systemctl enable wpa_supplicant.service >/dev/null 2>&1 || true
  systemctl restart wpa_supplicant.service >/dev/null 2>&1 || true

  if systemctl list-unit-files | grep -q '^dhcpcd\.service'; then
    systemctl enable dhcpcd.service >/dev/null 2>&1 || true
    systemctl restart dhcpcd.service >/dev/null 2>&1 || true
  fi

  return 0
}

is_valid_ipv4() {
  python3 - "$1" <<'PY'
import ipaddress
import sys
try:
    value = ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)
raise SystemExit(0 if value.version == 4 else 1)
PY
}

ask_server_query_config() {
  say "fragebogenpi-Server und Query-Intervall konfigurieren"

  local value=""
  while true; do
    read -r -p "IP-Adresse des fragebogenpi-Servers [${FRAGEBOGENPI_SERVER_IP}]: " value
    value="${value:-$FRAGEBOGENPI_SERVER_IP}"
    if is_valid_ipv4 "$value"; then
      FRAGEBOGENPI_SERVER_IP="$value"
      break
    fi
    echo "Bitte eine gültige IPv4-Adresse eingeben." >&2
  done

  while true; do
    read -r -p "Abfrageintervall in Sekunden [${QUERY_INTERVAL_SECONDS}]: " value
    value="${value:-$QUERY_INTERVAL_SECONDS}"
    if [[ "$value" =~ ^([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]] && awk -v n="$value" 'BEGIN { exit !(n > 0) }'; then
      QUERY_INTERVAL_SECONDS="$value"
      break
    fi
    echo "Bitte eine positive Zahl eingeben." >&2
  done
}

write_server_query_config() {
  say "Schreibe Server-Konfiguration außerhalb des Webroots"
  mkdir -p "$SERVER_CONFIG_DIR"
  cat >"$SERVER_CONFIG_JSON" <<EOF
{
  "server_url": "http://${FRAGEBOGENPI_SERVER_IP}/wartezimmer-server.php",
  "query_interval_seconds": ${QUERY_INTERVAL_SECONDS}
}
EOF
  chown root:"$INFODISPLAY_GROUP" "$SERVER_CONFIG_DIR" "$SERVER_CONFIG_JSON"
  chmod 0750 "$SERVER_CONFIG_DIR"
  chmod 0640 "$SERVER_CONFIG_JSON"
}

check_waiting_room_server_reachable() {
  say "Prüfe Wartezimmer-Server ohne GDT-Abruf"
  local url="http://${FRAGEBOGENPI_SERVER_IP}/wartezimmer-server.php"
  local attempt
  for attempt in $(seq 1 15); do
    if curl -fsSI --max-time 3 "$url" >/dev/null 2>&1; then
      say "Wartezimmer-Server erreichbar: ${url}"
      return 0
    fi
    sleep 1
  done
  echo "WARNUNG: ${url} ist derzeit nicht erreichbar. Die Installation wird trotzdem fortgesetzt." >&2
}

configure_firewall_wlan_only() {
  say "Firewall (nftables): wlan0 inbound dicht (Ping+DHCP+established), eth0 offen"

  backup_file /etc/nftables.conf
  cat >/etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0;

    iif "lo" accept
    ct state established,related accept

    # LAN: alles offen
    iif "eth0" accept

    # WLAN: DHCP client replies
    iif "wlan0" udp sport 67 udp dport 68 accept
    iif "wlan0" udp sport 547 udp dport 546 accept

    # WLAN: Ping erlauben
    iif "wlan0" ip protocol icmp accept
    iif "wlan0" ip6 nexthdr icmpv6 accept

    # WLAN: sonst nichts rein
    iif "wlan0" drop

    drop
  }

  chain forward {
    type filter hook forward priority 0;
    drop
  }

  chain output {
    type filter hook output priority 0;
    accept
  }
}
EOF

  systemctl enable nftables >/dev/null 2>&1 || true
  systemctl restart nftables
}

configure_apache_open_lan() {
  say "Apache: im LAN erreichbar (0.0.0.0:80), ohne Zugriffs-/Fehlerlog"

  backup_file /etc/apache2/ports.conf
  cat >/etc/apache2/ports.conf <<'EOF'
# Managed by fragebogenpi wartezimmerbildschirm installer
Listen 0.0.0.0:80

<IfModule ssl_module>
  Listen 0.0.0.0:443
</IfModule>

<IfModule mod_gnutls.c>
  Listen 0.0.0.0:443
</IfModule>
EOF

  backup_file /etc/apache2/sites-available/000-default.conf
  cat >/etc/apache2/sites-available/000-default.conf <<'EOF'
# Managed by fragebogenpi wartezimmerbildschirm installer
<VirtualHost *:80>
  ServerAdmin webmaster@localhost
  DocumentRoot /var/www/html

  ErrorLog /dev/null
  CustomLog /dev/null combined

  <Directory /var/www/html>
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
  </Directory>

  DirectoryIndex wartezimmer.php index.php index.html

  <Directory /var/www/html/videos>
    php_admin_flag engine off
  </Directory>
  <Directory /var/www/html/images>
    php_admin_flag engine off
  </Directory>
  <Directory /var/www/html/sounds>
    php_admin_flag engine off
  </Directory>
  <Directory /var/www/html/assets>
    php_admin_flag engine off
  </Directory>
</VirtualHost>
EOF

  systemctl enable apache2
  systemctl restart apache2
}

download_asset_if_missing() {
  local url="$1"
  local dest="$2"

  if [[ -s "$dest" ]]; then
    return 0
  fi

  local d
  d="$(dirname "$dest")"
  mkdir -p "$d"

  local tmp
  tmp="$(mktemp "${d}/.$(basename "$dest").tmp.XXXXXX")"

  if ! curl -fL --retry 6 --retry-delay 1 --retry-all-errors -o "$tmp" "$url"; then
    rm -f "$tmp" || true
    die "Download fehlgeschlagen: ${url}"
  fi

  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp" || true
    die "Download ist leer: ${url}"
  fi

  mv -f "$tmp" "$dest"
  chmod 0664 "$dest" || true
}

install_webroot_files() {
  say "Webroot-Struktur + Dateien anlegen in /var/www/html"
  mkdir -p \
    "${WEBROOT_DIR}/videos" \
    "${WEBROOT_DIR}/images" \
    "${WEBROOT_DIR}/sounds" \
    "${WEBROOT_DIR}/assets" \
    "${WEBROOT_DIR}/helper"

  say "Bootstrap: jsbach.m4a + Beispielvideo (falls fehlend)"
  download_asset_if_missing "$JSBACH_URL" "$JSBACH_DEST"
  download_asset_if_missing "$EXAMPLEVIDEO_URL" "$EXAMPLEVIDEO_DEST"

  say "Schreibe wartezimmer.php"
  cat >"${WEBROOT_DIR}/wartezimmer.php" <<EOF
<?php
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Pragma: no-cache");
?><!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>fragebogenpi wartezimmerbildschirm</title>
  <style>
    html, body { margin:0; padding:0; width:100%; height:100%; background:#000; overflow:hidden; }
    #stage { position:fixed; inset:0; display:flex; align-items:center; justify-content:center; background:#000; }
    video, img { width:100%; height:100%; object-fit:cover; }

    #overlay {
      position:fixed; inset:0; display:none;
      align-items:center; justify-content:center;
      background: rgba(0,0,0,0.75);
      color:#fff;
      font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif;
      text-align:center;
      padding: 6vh 6vw;
      z-index: 10;
    }
    #overlay .box {
      width:min(1200px, 90vw);
      border: 2px solid rgba(255,255,255,0.25);
      border-radius: 18px;
      padding: 5vh 4vw;
      background: rgba(20,20,20,0.65);
    }
    #overlay .title { font-size: clamp(28px, 5vw, 72px); font-weight: 700; margin: 0 0 2vh 0; }
    #overlay .target { font-size: clamp(22px, 3.5vw, 48px); opacity: 0.95; margin: 0; }
    #overlay .small  { font-size: clamp(14px, 2vw, 22px); opacity: 0.7; margin-top: 3vh; }

    #footer {
      position: fixed;
      left: 0;
      right: 0;
      bottom: 0;
      padding: 10px 14px;
      font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif;
      font-size: 18px;
      letter-spacing: 0.2px;
      color: rgba(255,255,255,0.90);
      text-align: center;
      background: rgba(0,0,0,0.35);
      text-shadow: 0 1px 2px rgba(0,0,0,0.7);
      pointer-events: none;
      display: none;
      z-index: 11;
    }
  </style>
</head>
<body>
  <div id="stage"></div>

  <div id="overlay">
    <div class="box">
      <div class="title" id="ovTitle">Aufruf</div>
      <div class="target" id="ovTarget"></div>
      <div class="small" id="ovSource"></div>
    </div>
  </div>

  <div id="footer">Dr. Thomas Kienzle · fragebogenpi.de wartezimmerbildschirm · v${VERSION}</div>

  <audio id="chime" preload="auto"></audio>

<script>
(async () => {
  const stage   = document.getElementById('stage');
  const overlay = document.getElementById('overlay');
  const footer  = document.getElementById('footer');
  const ovTitle = document.getElementById('ovTitle');
  const ovTarget= document.getElementById('ovTarget');
  const ovSource= document.getElementById('ovSource');
  const chime   = document.getElementById('chime');

  let cfg = null;
  let mode = "video";
  let displaySeconds = 10;
  let slideshowInterval = 10;
  let restartAfterCall = false;

  let videoSoundEnabled = false;
  let videoVolume = 0.15;
  let chimeVolume = 1.0;

  let videoEl = null;
  let imgEl   = null;
  let playlist = [];
  let idx = 0;
  let slideTimer = null;
  let pausedByCall = false;

  let videoWatchdog = null;
  let starting = false;

  let duckActive = false;
  let prevMuted = null;
  let prevVolume = null;

  function clamp01(x) {
    const n = Number(x);
    if (!isFinite(n)) return 0;
    return Math.max(0, Math.min(1, n));
  }

  function clearStage() {
    stage.innerHTML = "";
    videoEl = null;
    imgEl = null;
    if (videoWatchdog) { clearInterval(videoWatchdog); videoWatchdog = null; }
  }

  async function loadConfig() {
    const r = await fetch('wartezimmer.json', {cache:'no-store'});
    cfg = await r.json();

    mode = cfg.mode || "video";
    displaySeconds = Number(cfg.display_seconds ?? 10);
    slideshowInterval = Number(cfg.slideshow_interval_seconds ?? 10);
    restartAfterCall = Boolean(cfg.playlist_restart_on_call_end ?? false);

    const a = (cfg.audio && typeof cfg.audio === 'object') ? cfg.audio : {};
    videoSoundEnabled = Boolean(a.video_sound_enabled ?? false);
    videoVolume = clamp01(a.video_volume ?? 0.15);
    chimeVolume = clamp01(a.chime_volume ?? 1.0);
  }

  async function listMedia(kind) {
    const r = await fetch(\`helper/list_media.php?kind=\${encodeURIComponent(kind)}\`, {cache:'no-store'});
    if (!r.ok) return [];
    const j = await r.json();
    return Array.isArray(j.files) ? j.files : [];
  }

  async function ensurePlaylist(kind) {
    for (let i = 0; i < 60; i++) {
      const files = await listMedia(kind);
      if (files.length > 0) return files;
      await new Promise(res => setTimeout(res, 1000));
    }
    return [];
  }

  function nextIndex() {
    if (playlist.length === 0) return 0;
    return (idx + 1) % playlist.length;
  }

  function videoSrcForIndex(i) {
    idx = (playlist.length === 0) ? 0 : (i % playlist.length);
    return \`videos/\${encodeURIComponent(playlist[idx])}\`;
  }

  function applyVideoAudioConfig() {
    if (!videoEl) return;
    videoEl.muted = !videoSoundEnabled;
    videoEl.volume = videoSoundEnabled ? videoVolume : 0.0;
  }

  async function tryPlayVideo() {
    if (!videoEl) return false;
    try {
      applyVideoAudioConfig();
      const p = videoEl.play();
      if (p && typeof p.then === 'function') await p;
      return true;
    } catch (e) {
      return false;
    }
  }

  async function skipVideo(reason) {
    if (!videoEl || playlist.length === 0) return;
    const ni = nextIndex();
    videoEl.src = videoSrcForIndex(ni);
    await tryPlayVideo();
  }

  function attachVideoSelfHeal() {
    if (!videoEl) return;

    videoEl.addEventListener('error', () => { skipVideo('error'); });
    videoEl.addEventListener('ended', () => { skipVideo('ended'); });

    let lastOk = Date.now();
    const markOk = () => { lastOk = Date.now(); };
    videoEl.addEventListener('playing', markOk);
    videoEl.addEventListener('canplay', markOk);
    videoEl.addEventListener('timeupdate', markOk);

    videoWatchdog = setInterval(async () => {
      if (pausedByCall) return;
      if (!videoEl) return;
      const age = Date.now() - lastOk;
      if (age < 2500) return;

      const ok = await tryPlayVideo();
      if (!ok) await skipVideo('watchdog');
      else lastOk = Date.now();
    }, 1000);
  }

  async function startVideoMode() {
    clearStage();
    videoEl = document.createElement('video');
    videoEl.autoplay = true;
    videoEl.playsInline = true;
    videoEl.controls = false;
    videoEl.preload = "auto";
    stage.appendChild(videoEl);

    playlist = await ensurePlaylist("videos");
    if (playlist.length === 0) return;

    videoEl.src = videoSrcForIndex(0);
    attachVideoSelfHeal();
    await tryPlayVideo();
  }

  async function startSlideshowMode() {
    clearStage();
    imgEl = document.createElement('img');
    stage.appendChild(imgEl);

    playlist = await ensurePlaylist("images");
    if (playlist.length === 0) return;

    const showIndex = (i) => {
      idx = i % playlist.length;
      imgEl.src = \`images/\${encodeURIComponent(playlist[idx])}\`;
    };

    showIndex(0);
    slideTimer = setInterval(() => {
      if (!pausedByCall) showIndex((idx + 1) % playlist.length);
    }, Math.max(1, slideshowInterval) * 1000);
  }

  function stopSlideshowTimer() {
    if (slideTimer) { clearInterval(slideTimer); slideTimer = null; }
  }

  async function startNormalMode() {
    if (starting) return;
    starting = true;
    try {
      pausedByCall = false;
      stopSlideshowTimer();
      if (mode === "slideshow") await startSlideshowMode();
      else await startVideoMode();
    } finally {
      starting = false;
    }
  }

  function pauseNormal() {
    pausedByCall = true;
    if (videoEl) { try { videoEl.pause(); } catch(e) {} }
  }

  async function resumeNormal() {
    pausedByCall = false;

    if (duckActive && videoEl) {
      try {
        if (prevMuted !== null) videoEl.muted = prevMuted;
        if (prevVolume !== null) videoEl.volume = prevVolume;
      } catch(e) {}
      duckActive = false;
      prevMuted = null;
      prevVolume = null;
      try { applyVideoAudioConfig(); } catch(e) {}
    }

    if (restartAfterCall) {
      await startNormalMode();
      return;
    }
    if (videoEl) await tryPlayVideo();
  }

  async function playChime(soundPath) {
    try {
      chime.pause();
      chime.currentTime = 0;
      chime.volume = chimeVolume;
      chime.src = soundPath;
      await chime.play();
    } catch(e) {}
  }

  function duckVideoAudioForCall() {
    if (!videoEl) return;
    if (duckActive) return;
    try {
      prevMuted = videoEl.muted;
      prevVolume = videoEl.volume;
      videoEl.muted = true;
      videoEl.volume = 0.0;
      duckActive = true;
    } catch(e) {}
  }

  function showOverlay(text, target, source) {
    ovTitle.textContent = text || "Aufruf";
    ovTarget.textContent = target || "";
    ovSource.textContent = source || "";
    overlay.style.display = "flex";
    footer.style.display = "block";
    duckVideoAudioForCall();
  }

  function hideOverlay() {
    overlay.style.display = "none";
    footer.style.display = "none";
  }

  function connectEvents() {
    const es = new EventSource("http://127.0.0.1:8765/events");
    es.onmessage = async (ev) => {
      let data = null;
      try { data = JSON.parse(ev.data); } catch(e) { return; }
      if (!data || data.type !== "call") return;

      pauseNormal();
      showOverlay(data.display_text || "Aufruf", data.target || "", data.source_id || "");

      const sound = data.sound || ("sounds/" + (cfg.default_sound || "jsbach.m4a"));
      await playChime(sound);

      const ms = Math.max(1, Number(data.display_seconds ?? displaySeconds)) * 1000;
      setTimeout(async () => {
        hideOverlay();
        await resumeNormal();
      }, ms);
    };

    es.onerror = () => {
      try { es.close(); } catch(e) {}
      setTimeout(connectEvents, 2000);
    };
  }

  function installFocusHeal() {
    const heal = async () => {
      if (pausedByCall) return;
      await startNormalMode();
      await resumeNormal();
    };
    window.addEventListener('focus', heal);
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) heal();
    });
  }

  await loadConfig();
  await startNormalMode();
  connectEvents();
  installFocusHeal();

  setInterval(async () => {
    try {
      const oldMode = mode;
      await loadConfig();
      if (mode !== oldMode) await startNormalMode();
    } catch(e) {}
  }, 5000);
})();
</script>
</body>
</html>
EOF

  say "Schreibe helper/list_media.php"
  cat >"${WEBROOT_DIR}/helper/list_media.php" <<'EOF'
<?php
header("Content-Type: application/json; charset=utf-8");
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Pragma: no-cache");

$kind = isset($_GET["kind"]) ? $_GET["kind"] : "";
$allowed = ["videos", "images", "sounds"];
if (!in_array($kind, $allowed, true)) {
  http_response_code(400);
  echo json_encode(["error" => "invalid kind"], JSON_UNESCAPED_UNICODE);
  exit;
}

$base = realpath(__DIR__ . "/..");
$dir  = realpath($base . "/" . $kind);
if ($base === false || $dir === false || strpos($dir, $base . DIRECTORY_SEPARATOR) !== 0) {
  http_response_code(500);
  echo json_encode(["error" => "path error"], JSON_UNESCAPED_UNICODE);
  exit;
}

$exts = [];
if ($kind === "videos") $exts = ["mp4", "m4v"];
if ($kind === "images") $exts = ["jpg", "jpeg", "png", "webp"];
if ($kind === "sounds") $exts = ["mp3", "m4a"];

$files = [];
$dh = opendir($dir);
if ($dh !== false) {
  while (($f = readdir($dh)) !== false) {
    if ($f === "." || $f === "..") continue;
    if (strpos($f, '.') === 0) continue;  // dotfiles + AppleDouble (._*)
    if ($f === "Thumbs.db" || $f === "desktop.ini") continue;

    $p = $dir . DIRECTORY_SEPARATOR . $f;
    if (!is_file($p)) continue;

    $e = strtolower(pathinfo($f, PATHINFO_EXTENSION));
    if (!in_array($e, $exts, true)) continue;

    $files[] = $f;
  }
  closedir($dh);
}

sort($files, SORT_STRING);
echo json_encode(["files" => $files], JSON_UNESCAPED_UNICODE);
EOF

  say "Schreibe wartezimmer.json"
  cat >"${CONFIG_JSON}" <<'EOF'
{
  "version": "1.5.3",

  "_comment0": "Server-IP und Query-Intervall liegen außerhalb des Webroots in /etc/fragebogenpi-wartezimmer/server.json",
  "_comment1": "Die Namenskürzung erfolgt datensparsam auf dem fragebogenpi-Server.",

  "mode": "video",
  "display_seconds": 10,
  "video_dir": "videos",
  "image_dir": "images",
  "sound_dir": "sounds",
  "default_sound": "jsbach.m4a",
  "slideshow_interval_seconds": 10,
  "playlist_restart_on_call_end": false,

  "audio": {
    "video_sound_enabled": false,
    "video_volume": 0.15,
    "chime_volume": 1.0
  }
}
EOF

  say "Entferne veraltete lokale GDT-Löschskripte"
  backup_file "${WEBROOT_DIR}/loesche-sprechzimmer1.php"
  backup_file "${WEBROOT_DIR}/loesche-sprechzimmer2.php"
  rm -f "${WEBROOT_DIR}/loesche-sprechzimmer1.php" "${WEBROOT_DIR}/loesche-sprechzimmer2.php"

  cat >"${WEBROOT_DIR}/README_WARTEZIMMER.txt" <<EOF
${APP_NAME} v${VERSION}

Startseite:
- http://<pi-ip>/wartezimmer.php
- Kiosk öffnet lokal: http://127.0.0.1/wartezimmer.php

Konfiguration:
- ${CONFIG_JSON}
- ${SERVER_CONFIG_JSON}

Aufrufweg:
- Die Praxissoftware schreibt je Wartezimmer eine GDT-Datei in \\\\fragebogenpi\\wartezimmer-GDT.
- Der Dateiname bestimmt das Ziel, z.B. Wartezimmer_1.gdt -> Wartezimmer 1.
- Der Wartezimmer-Pi fragt ausschließlich wartezimmer-server.php ab.
- Er erhält nur den auf fragebogenpi formatierten Namen und das Ziel, niemals die rohe GDT-Datei.

Audio:
- wartezimmer.json -> audio.video_sound_enabled (default false)
- wartezimmer.json -> audio.video_volume (0..1)
- wartezimmer.json -> audio.chime_volume (0..1)
- default_sound: jsbach.m4a (liegt in /var/www/html/sounds/)

Video:
- Beispielvideo (falls fehlend): /var/www/html/videos/zzz_beispielvideo.mp4

Firewall:
- eth0 offen
- wlan0 inbound blockiert (nur established/related, DHCP, Ping)
EOF
}

configure_permissions_and_samba_ready() {
  say "User/Gruppe/Rechte: SMB-Guest Schreibzugriff (wie bisher)"

  ensure_group "$INFODISPLAY_GROUP"
  ensure_user_infodisplay

  usermod -a -G "$INFODISPLAY_GROUP" "$INFODISPLAY_USER" >/dev/null 2>&1 || true
  usermod -a -G "$INFODISPLAY_GROUP" "www-data" >/dev/null 2>&1 || true

  chown -R "${INFODISPLAY_USER}:${INFODISPLAY_GROUP}" "${WEBROOT_DIR}"
  chmod 2775 "${WEBROOT_DIR}"
  find "${WEBROOT_DIR}" -type d -exec chmod 2775 {} \;
  find "${WEBROOT_DIR}" -type f -exec chmod 0664 {} \;

}

configure_samba() {
  say "Samba: Guest RW Share auf gesamtes Webroot (/var/www/html)"
  backup_file /etc/samba/smb.conf

  cat >/etc/samba/smb.conf <<EOF
# Managed by ${APP_NAME} installer v${VERSION}
[global]
   workgroup = WORKGROUP
   server string = ${APP_NAME}
   server role = standalone server

   map to guest = Bad User
   guest account = ${INFODISPLAY_USER}

   logging = file
   log file = /dev/null
   log level = 0
   max log size = 0

   server min protocol = SMB2
   client min protocol = SMB2

[webroot]
   comment = ${APP_NAME} Webroot (Guest RW)
   path = ${WEBROOT_DIR}
   browseable = yes
   read only = no
   guest ok = yes
   public = yes

   force user = ${INFODISPLAY_USER}
   force group = ${INFODISPLAY_GROUP}

   create mask = 0664
   directory mask = 2775
EOF

  systemctl enable smbd nmbd >/dev/null 2>&1 || true
  systemctl restart smbd nmbd
}

install_backend() {
  say "Backend: einzelner Query auf wartezimmer-server.php, ohne Logging"

  cat >/usr/local/bin/infodisplay-backend.py <<'PYEOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import asyncio
import json
from typing import Any, Dict, List, Optional

from aiohttp import ClientSession, ClientTimeout, web

SERVER_CONFIG_PATH = "/etc/fragebogenpi-wartezimmer/server.json"
DISPLAY_CONFIG_PATH = "/var/www/html/wartezimmer.json"


def load_json(path: str) -> Optional[Dict[str, Any]]:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            value = json.load(handle)
        return value if isinstance(value, dict) else None
    except Exception:
        return None


class EventHub:
    def __init__(self) -> None:
        self._clients: List[asyncio.Queue] = []

    def subscribe(self) -> asyncio.Queue:
        queue: asyncio.Queue = asyncio.Queue(maxsize=20)
        self._clients.append(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue) -> None:
        try:
            self._clients.remove(queue)
        except ValueError:
            pass

    async def publish(self, payload: Dict[str, Any]) -> None:
        for queue in list(self._clients):
            try:
                queue.put_nowait(payload)
            except asyncio.QueueFull:
                self.unsubscribe(queue)


async def sse_events(request: web.Request) -> web.StreamResponse:
    hub: EventHub = request.app["hub"]
    queue = hub.subscribe()

    response = web.StreamResponse(
        status=200,
        headers={
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
        },
    )
    await response.prepare(request)

    async def heartbeat() -> None:
        while True:
            try:
                await response.write(b": ping\n\n")
            except Exception:
                return
            await asyncio.sleep(10)

    heartbeat_task = asyncio.create_task(heartbeat())
    try:
        while True:
            payload = await queue.get()
            data = json.dumps(payload, ensure_ascii=False)
            await response.write(f"data: {data}\n\n".encode("utf-8"))
    except Exception:
        pass
    finally:
        heartbeat_task.cancel()
        hub.unsubscribe(queue)

    return response


def positive_number(value: Any, fallback: float) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return fallback
    return number if number > 0 else fallback


async def poll_loop(app: web.Application) -> None:
    hub: EventHub = app["hub"]
    timeout = ClientTimeout(total=5.0)

    async with ClientSession(timeout=timeout) as session:
        while True:
            server_config = load_json(SERVER_CONFIG_PATH) or {}
            server_url = str(server_config.get("server_url", "")).strip()
            interval = positive_number(
                server_config.get("query_interval_seconds", 3),
                3.0,
            )

            if not server_url:
                await asyncio.sleep(interval)
                continue

            try:
                async with session.get(server_url) as response:
                    if response.status != 200:
                        await asyncio.sleep(interval)
                        continue
                    call = await response.json(content_type=None)
            except Exception:
                await asyncio.sleep(interval)
                continue

            if not isinstance(call, dict):
                await asyncio.sleep(interval)
                continue

            display_text = str(call.get("display_text", "")).strip()
            target = str(call.get("target", "")).strip()
            if not display_text and not target:
                await asyncio.sleep(interval)
                continue

            display_config = load_json(DISPLAY_CONFIG_PATH) or {}
            sound_dir = str(display_config.get("sound_dir", "sounds")).strip() or "sounds"
            default_sound = str(display_config.get("default_sound", "jsbach.m4a")).strip() or "jsbach.m4a"
            display_seconds = positive_number(
                display_config.get("display_seconds", 10),
                10.0,
            )

            await hub.publish(
                {
                    "type": "call",
                    "display_text": display_text or "Aufruf",
                    "target": target,
                    "source_id": "",
                    "sound": f"{sound_dir}/{default_sound}",
                    "display_seconds": display_seconds,
                }
            )

            # Erst nach Ende der Anzeige wird die nächste Datei abgefragt.
            await asyncio.sleep(max(display_seconds, interval))


async def on_startup(app: web.Application) -> None:
    app["poll_task"] = asyncio.create_task(poll_loop(app))


async def on_cleanup(app: web.Application) -> None:
    task = app.get("poll_task")
    if task:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass


def main() -> None:
    app = web.Application()
    app["hub"] = EventHub()
    app.router.add_get("/events", sse_events)
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)
    web.run_app(
        app,
        host="127.0.0.1",
        port=8765,
        access_log=None,
        print=None,
    )


if __name__ == "__main__":
    main()
PYEOF

  chmod 0755 /usr/local/bin/infodisplay-backend.py

  cat >/etc/systemd/system/infodisplay-backend.service <<'EOF'
[Unit]
Description=fragebogenpi wartezimmerbildschirm backend (einzelner Server-Query)
After=network-online.target apache2.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 -u /usr/local/bin/infodisplay-backend.py
Restart=always
RestartSec=2
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now infodisplay-backend.service
}

install_firefox_kiosk_script() {
  say "Installiere /usr/local/bin/wartezimmer_firefox_kiosk.sh"
  cat >/usr/local/bin/wartezimmer_firefox_kiosk.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${1:-pi}"
URL="${2:-http://127.0.0.1/wartezimmer.php}"

HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
[[ -n "$HOME_DIR" ]] || HOME_DIR="/home/${USER_NAME}"

export HOME="$HOME_DIR"

# Firefox binary robust wählen
FF="firefox"
if command -v firefox-esr >/dev/null 2>&1; then
  FF="firefox-esr"
elif command -v firefox >/dev/null 2>&1; then
  FF="firefox"
fi

BASE="$HOME_DIR/.mozilla/firefox"
INI="$HOME_DIR/.mozilla/firefox/profiles.ini"

mkdir -p "$BASE"

# Profil "kiosk" anlegen (falls noch nicht vorhanden)
"$FF" -CreateProfile "kiosk" >/dev/null 2>&1 || true

# profiles.ini muss existieren (mit kurzer Warte-/Retry-Schleife)
for _i in $(seq 1 50); do
  [[ -f "$INI" ]] && break
  sleep 0.1
done
[[ -f "$INI" ]]

# Pfad zum Profil "kiosk" aus profiles.ini holen
PROFILE_REL="$(awk -F= '
  $0 ~ /^\[Profile/ {inprof=0}
  $0 ~ /^Name=kiosk$/ {inprof=1}
  inprof && $1=="Path" {print $2; exit}
' "$INI")"

[[ -n "$PROFILE_REL" ]]

PROFILE_DIR="$BASE/$PROFILE_REL"
mkdir -p "$PROFILE_DIR"

# Autoplay + Audio sauber erlauben (inkl. WebAudio)
cat >"$PROFILE_DIR/user.js" <<'PREFS'
/*** KIOSK: Autoplay erlauben (Audio + Video) ***/
user_pref("media.autoplay.default", 0);                  // 0=Allow
user_pref("media.autoplay.blocking_policy", 0);          // liberal
user_pref("media.autoplay.block-webaudio", false);       // WICHTIG
user_pref("media.autoplay.allow-muted", true);

/*** Permission-Defaults (Autoplay) explizit erlauben ***/
user_pref("permissions.default.autoplay", 0);

/*** weniger Dialoge ***/
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
PREFS

# Eventuell gespeicherte Site-Permissions entfernen (kann Autoplay blocken)
rm -f "$PROFILE_DIR/permissions.sqlite" \
      "$PROFILE_DIR/content-prefs.sqlite" \
      "$PROFILE_DIR/content-prefs.sqlite-wal" \
      "$PROFILE_DIR/content-prefs.sqlite-shm" || true

# Ownership korrigieren (nur wenn als root gestartet)
if [[ "${EUID}" -eq 0 ]]; then
  chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR/.mozilla/firefox" || true
fi

exec "$FF" -P kiosk --kiosk --no-remote "$URL"
EOF
  chmod +x /usr/local/bin/wartezimmer_firefox_kiosk.sh
}

configure_kiosk() {
  say "Kiosk: Autologin + Openbox autostart + Firefox"

  ensure_kiosk_user
  install_firefox_kiosk_script

  mkdir -p /etc/lightdm/lightdm.conf.d
  cat >/etc/lightdm/lightdm.conf.d/50-wartezimmer.conf <<EOF
# Managed by ${APP_NAME} installer v${VERSION}
[Seat:*]
autologin-user=${KIOSK_USER}
autologin-user-timeout=0
user-session=openbox
EOF

  mkdir -p "${KIOSK_HOME}/.config/openbox"
  chown -R "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/.config"

  cat >"${KIOSK_HOME}/.config/openbox/autostart" <<EOF
# Managed by ${APP_NAME} installer v${VERSION}

unclutter -idle 0.5 -root &

xset s off
xset s noblank
xset -dpms

# Warten bis lokale Endpunkte funktionieren + mindestens 1 Video vorhanden ist
for i in \$(seq 1 240); do
  if curl -fsS "http://127.0.0.1/wartezimmer.php" >/dev/null 2>&1 && \
     curl -fsS "http://127.0.0.1/wartezimmer.json" >/dev/null 2>&1 && \
     curl -fsS "http://127.0.0.1/helper/list_media.php?kind=videos" | grep -q '\.mp4"\|\.m4v"'; then
      break
  fi
  sleep 0.5
done

/usr/local/bin/wartezimmer_firefox_kiosk.sh "${KIOSK_USER}" "http://127.0.0.1/wartezimmer.php"
EOF

  chown "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/.config/openbox/autostart"
  chmod 0755 "${KIOSK_HOME}/.config/openbox/autostart"

  systemctl set-default graphical.target
  systemctl enable lightdm
}

ask_reboot_now() {
  # Nur wenn interaktiv (TTY)
  if [[ ! -t 0 ]]; then
    return 0
  fi
  echo
  local ans
  read -r -p "Reboot jetzt? [y/N]: " ans
  if [[ "$ans" =~ ^([yY]|yes|YES)$ ]]; then
    reboot
  fi
}

main() {
  need_root
  say "${APP_NAME} — Installer v${VERSION}"

  apt_install

  ensure_group "$INFODISPLAY_GROUP"
  ensure_user_infodisplay

  ask_hostname_and_set_robust
  ask_wlan_enable_and_configure || true
  ask_server_query_config

  configure_firewall_wlan_only

  install_webroot_files
  configure_permissions_and_samba_ready
  write_server_query_config
  configure_apache_open_lan
  configure_samba

  install_backend
  configure_kiosk
  check_waiting_room_server_reachable

  say "Fertig."
  echo
  echo "Wichtige URLs:"
  echo "  - Web:   http://<pi-ip>/wartezimmer.php"
  echo "  - Lokal: http://127.0.0.1/wartezimmer.php"
  echo "  - Server: http://${FRAGEBOGENPI_SERVER_IP}/wartezimmer-server.php"
  echo "  - WLAN-SSID: ${WLAN_SSID}"
  echo "  - Query-Intervall: ${QUERY_INTERVAL_SECONDS} Sekunden"
  echo
  echo "Firefox Kiosk Start (manuell, falls nötig):"
  echo "  - sudo -u ${KIOSK_USER} firefox-esr -P kiosk --kiosk --no-remote http://127.0.0.1/wartezimmer.php"

  ask_reboot_now
}

main "$@"
