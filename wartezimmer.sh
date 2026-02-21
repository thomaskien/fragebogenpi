#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# fragebogenpi wartezimmerbildschirm — Installer
# Version: 1.3.6
# Stand:   2026-02-21
# Autor:   Dr. Thomas Kienzle
#
# Ziel (konservativ):
# - Startverhalten wie 1.3.2: Kiosk startet Chromium direkt, ohne fragile wmctrl/xdotool-Fokus-Automatik.
# - Alle neuen Features bleiben erhalten:
#   - Hostname robust + cloud-init user-data hostname-Zeile ersetzen
#   - WLAN optional, Prompts über /dev/tty
#   - nftables: wlan0 inbound dicht (established/related, DHCP, Ping), eth0 offen
#   - Samba Guest RW Share auf /var/www/html
#   - Web-App: Video/Slideshow, Overlay + Footer nur bei Meldung, Audio Ducking, getrennte Volumes
#   - Dotfiles/._* filtern
#   - Fetch: rooms 1+2, display_seconds=10, delete scripts
#   - Name-Format optional (T. Kie.) konfigurierbar (Vor-/Nachname getrennt), Spaces/Hyphens ignorieren
#   - Sound bootstrap: jsbach.m4a (default_sound)
#   - Boot-Playback Stabilität: Web-App Self-Heal (watchdog -> reload wenn nötig)
#
# Changelog (komplett, ab 1.0):
# - 1.0: Basis Kiosk+Apache+PHP+Samba+Konfig.
# - 1.1: Webroot direkt, Guest RW, Fetch testweise localhost, Löschskript.
# - 1.2: Hostname/WLAN-Abfragen, Logging off.
# - 1.3: DPMS off, Anti-throttle Flags, Web-App self heal, dotfile filter, firewall wlan dicht.
# - 1.3.1: WLAN-Prompts robust (/dev/tty), Audio reset+duck.
# - 1.3.2: /boot/firmware/user-data hostname, rooms 1+2, README erweitert.
# - 1.3.3: Name-Format optional, jsbach.m4a bootstrap, sounds m4a erlaubt.
# - 1.3.4: Fix hostname user-data patch (Zeile ersetzen, nicht anhängen).
# - 1.3.5: (verworfen in der Praxis) Fokus/Reload via wmctrl/xdotool war nicht robust genug.
# - 1.3.6: Zurück zu 1.3.2 Startverhalten (kein wmctrl/xdotool).
#          Boot-Fix erfolgt jetzt zuverlässig in der Web-App selbst (watchdog reload),
#          ohne Window-Fokus-Race.
# ==============================================================================

APP_NAME="fragebogenpi wartezimmerbildschirm"
VERSION="1.3.6"

WEBROOT_DIR="/var/www/html"
CONFIG_JSON="${WEBROOT_DIR}/wartezimmer.json"

INFODISPLAY_USER="infodisplay"
INFODISPLAY_GROUP="infodisplay"

# Autologin/Kiosk user (dein System nutzt pi auf :0)
KIOSK_USER="pi"
KIOSK_HOME="/home/${KIOSK_USER}"

# RAM chromium profile/cache
RUN_CHROME_DIR="/run/wartezimmer-chromium"

# Sound bootstrap
BOOTSTRAP_SOUND_URL="https://github.com/thomaskien/fragebogenpi/raw/refs/heads/main/jsbach.m4a"
BOOTSTRAP_SOUND_PATH="${WEBROOT_DIR}/sounds/jsbach.m4a"

say() { echo -e "\n### $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() { [[ "${EUID}" -eq 0 ]] || die "Bitte als root ausführen."; }

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
  getent group "$g" >/dev/null 2>&1 || groupadd "$g"
}

ensure_user_infodisplay() {
  if id "$INFODISPLAY_USER" >/dev/null 2>&1; then return 0; fi
  say "Lege Benutzer an: ${INFODISPLAY_USER}"
  useradd -r -m -d "/var/lib/${INFODISPLAY_USER}" -s /usr/sbin/nologin -g "${INFODISPLAY_GROUP}" "${INFODISPLAY_USER}"
}

ensure_kiosk_user() {
  if id "$KIOSK_USER" >/dev/null 2>&1; then return 0; fi
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
    chromium \
    unclutter-xfixes \
    python3 python3-aiohttp python3-requests
}

# Hostname user-data patch (cloud-init) — robust + idempotent
patch_cloud_user_data_hostname() {
  local hn="$1"
  local ud="/boot/firmware/user-data"

  [[ -f "$ud" ]] || return 0
  grep -qE '^\s*#cloud-config\b' "$ud" || return 0
  grep -qE '^\s*hostname\s*:' "$ud" || return 0

  backup_file "$ud"

  HN="$hn" UD="$ud" python3 - <<'PY'
import os, re, pathlib
hn = os.environ["HN"]
ud = os.environ["UD"]
p = pathlib.Path(ud)
t = p.read_text(encoding="utf-8", errors="replace")
t2, n = re.subn(r'(?m)^(\s*hostname\s*:\s*).*$',
                r'\1' + hn, t, count=1)
p.write_text(t2, encoding="utf-8")
print("patched hostname lines:", n)
PY
}

ask_hostname_and_set_robust() {
  say "Hostname setzen (robust)"
  local hn
  if [[ -t 0 ]]; then
    read -r -p "Hostname [default: wartezimmer]: " hn
  else
    read -r -p "Hostname [default: wartezimmer]: " hn </dev/tty
  fi
  hn="${hn:-wartezimmer}"

  [[ "$hn" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]] || die "Ungültiger Hostname: '$hn'"

  say "Setze Hostname auf: $hn"
  echo "$hn" >/etc/hostname

  backup_file /etc/hosts
  if grep -qE '^127\.0\.1\.1' /etc/hosts; then
    sed -i -E "s/^127\.0\.1\.1\s+.*/127.0.1.1\t${hn}/" /etc/hosts
  else
    echo -e "127.0.1.1\t${hn}" >>/etc/hosts
  fi

  hostname "$hn" || true
  command -v hostnamectl >/dev/null 2>&1 && hostnamectl set-hostname "$hn" || true
  patch_cloud_user_data_hostname "$hn"
}

ask_wlan_enable_and_configure() {
  say "WLAN optional konfigurieren"
  local ans ssid pass

  if [[ -t 0 ]]; then
    read -r -p "WLAN aktivieren und konfigurieren? [Y/n]: " ans
  else
    read -r -p "WLAN aktivieren und konfigurieren? [Y/n]: " ans </dev/tty
  fi
  ans="${ans:-Y}"
  if [[ "$ans" =~ ^([nN]|no|NO)$ ]]; then
    say "WLAN-Konfiguration übersprungen."
    return 1
  fi

  if [[ -t 0 ]]; then
    read -r -p "WLAN SSID [default: fragebogenpi]: " ssid
  else
    read -r -p "WLAN SSID [default: fragebogenpi]: " ssid </dev/tty
  fi
  ssid="${ssid:-fragebogenpi}"

  echo -n "WLAN Passwort (WPA2/PSK): " >/dev/tty
  IFS= read -r -s pass </dev/tty
  echo >/dev/tty

  [[ -n "$ssid" ]] || die "SSID leer."
  [[ -n "$pass" ]] || die "Passwort leer."

  say "Schreibe /etc/wpa_supplicant/wpa_supplicant.conf (country=DE)"
  backup_file /etc/wpa_supplicant/wpa_supplicant.conf

  local tmp
  tmp="$(mktemp)"
  wpa_passphrase "$ssid" "$pass" >"$tmp"

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

    # WLAN: DHCP replies
    iif "wlan0" udp sport 67 udp dport 68 accept
    iif "wlan0" udp sport 547 udp dport 546 accept

    # WLAN: Ping erlauben
    iif "wlan0" ip protocol icmp accept
    iif "wlan0" ip6 nexthdr icmpv6 accept

    # WLAN: sonst nichts rein
    iif "wlan0" drop
    drop
  }

  chain forward { type filter hook forward priority 0; drop }
  chain output  { type filter hook output  priority 0; accept }
}
EOF
  systemctl enable nftables >/dev/null 2>&1 || true
  systemctl restart nftables
}

configure_chromium_policy() {
  say "Chromium Policy: Übersetzungsleiste deaktivieren"
  mkdir -p /etc/chromium/policies/managed
  cat >/etc/chromium/policies/managed/00-disable-translate.json <<'EOF'
{ "TranslateEnabled": false }
EOF
  mkdir -p /etc/chromium-browser/policies/managed || true
  cat >/etc/chromium-browser/policies/managed/00-disable-translate.json <<'EOF'
{ "TranslateEnabled": false }
EOF
}

configure_apache_open_lan() {
  say "Apache: im LAN erreichbar"
  mkdir -p "${WEBROOT_DIR}/logs"

  backup_file /etc/apache2/ports.conf
  cat >/etc/apache2/ports.conf <<'EOF'
Listen 0.0.0.0:80
EOF

  backup_file /etc/apache2/sites-available/000-default.conf
  cat >/etc/apache2/sites-available/000-default.conf <<'EOF'
<VirtualHost *:80>
  DocumentRoot /var/www/html

  ErrorLog /var/www/html/logs/apache_error.log
  CustomLog /var/www/html/logs/apache_access.log combined

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
</VirtualHost>
EOF

  systemctl enable apache2
  systemctl restart apache2
}

bootstrap_sound_file() {
  say "Bootstrap Sound: jsbach.m4a"
  mkdir -p "${WEBROOT_DIR}/sounds"
  curl -fL --retry 3 --retry-delay 2 -o "${BOOTSTRAP_SOUND_PATH}.tmp" "${BOOTSTRAP_SOUND_URL}"
  mv -f "${BOOTSTRAP_SOUND_PATH}.tmp" "${BOOTSTRAP_SOUND_PATH}"
}

install_webroot_files() {
  say "Webroot-Struktur + Dateien"
  mkdir -p \
    "${WEBROOT_DIR}/videos" \
    "${WEBROOT_DIR}/images" \
    "${WEBROOT_DIR}/sounds" \
    "${WEBROOT_DIR}/helper" \
    "${WEBROOT_DIR}/logs"

  bootstrap_sound_file

  # list_media.php: filter dotfiles/._*, allow mp4/m4v, images, sounds mp3+m4a
  cat >"${WEBROOT_DIR}/helper/list_media.php" <<'EOF'
<?php
header("Content-Type: application/json; charset=utf-8");
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Pragma: no-cache");

$kind = isset($_GET["kind"]) ? $_GET["kind"] : "";
$allowed = ["videos", "images", "sounds"];
if (!in_array($kind, $allowed, true)) { http_response_code(400); echo json_encode(["error"=>"invalid kind"]); exit; }

$base = realpath(__DIR__ . "/..");
$dir  = realpath($base . "/" . $kind);
if ($base === false || $dir === false || strpos($dir, $base . DIRECTORY_SEPARATOR) !== 0) {
  http_response_code(500); echo json_encode(["error"=>"path error"]); exit;
}

$exts = [];
if ($kind === "videos") $exts = ["mp4","m4v"];
if ($kind === "images") $exts = ["jpg","jpeg","png","webp"];
if ($kind === "sounds") $exts = ["mp3","m4a"];

$files = [];
$dh = opendir($dir);
if ($dh !== false) {
  while (($f = readdir($dh)) !== false) {
    if ($f === "." || $f === "..") continue;
    if (strpos($f, '.') === 0) continue;     // .*, includes ._*
    if (strpos($f, '._') === 0) continue;
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
echo json_encode(["files"=>$files], JSON_UNESCAPED_UNICODE);
EOF

  # wartezimmer.json (rooms 1+2, display_seconds=10, name_format off by default, default_sound jsbach.m4a)
  cat >"${CONFIG_JSON}" <<'EOF'
{
  "version": "1.3.6",
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
  },

  "name_format": {
    "enabled": false,
    "first_name": { "enabled": true, "letters": 1, "dot": true },
    "last_name":  { "enabled": true, "letters": 3, "dot": true }
  },

  "fetch": {
    "enabled": true,
    "poll_interval_ms": 500,
    "max_jobs_per_room_per_cycle": 10,
    "rooms": [
      {
        "id": "sprechzimmer1",
        "target": "Bitte ins Sprechzimmer 1",
        "_comment0": "am besten die dateien auf http://fragebogenpi.local/sprechzimmer1.gdt",
        "_comment1": "alternativ kann die gdt ueber smb://wartezimmer/webroot geschrieben werden",
        "fetch_url": "http://127.0.0.1/sprechzimmer1.gdt",
        "_comment2": "am besten die dateien auf http://fragebogenpi.local/loesche-sprechzimmer1.php",
        "_comment3": "die datei loesche muss editiert werden je nach name den man waehlt",
        "delete_url": "http://127.0.0.1/loesche-sprechzimmer1.php",
        "enabled": true
      },
      {
        "id": "sprechzimmer2",
        "target": "Bitte ins Sprechzimmer 2",
        "fetch_url": "http://127.0.0.1/sprechzimmer2.gdt",
        "delete_url": "http://127.0.0.1/loesche-sprechzimmer2.php",
        "enabled": true
      }
    ]
  },

  "logging": {
    "enabled": false,
    "sink": "file",
    "level": "debug",
    "log_file": "/var/www/html/logs/backend.log"
  }
}
EOF

  # delete scripts (hardcoded file)
  cat >"${WEBROOT_DIR}/loesche-sprechzimmer1.php" <<'EOF'
<?php
header("Content-Type: text/plain; charset=utf-8");
header("Cache-Control: no-store");
$path = "/var/www/html/sprechzimmer1.gdt";
if (substr($path, -4) !== ".gdt") { http_response_code(500); echo "bad extension\n"; exit; }
if (!file_exists($path)) { http_response_code(204); echo "no file\n"; exit; }
if (@unlink($path)) { http_response_code(200); echo "deleted\n"; exit; }
http_response_code(500); echo "delete failed\n";
EOF

  cat >"${WEBROOT_DIR}/loesche-sprechzimmer2.php" <<'EOF'
<?php
header("Content-Type: text/plain; charset=utf-8");
header("Cache-Control: no-store");
$path = "/var/www/html/sprechzimmer2.gdt";
if (substr($path, -4) !== ".gdt") { http_response_code(500); echo "bad extension\n"; exit; }
if (!file_exists($path)) { http_response_code(204); echo "no file\n"; exit; }
if (@unlink($path)) { http_response_code(200); echo "deleted\n"; exit; }
http_response_code(500); echo "delete failed\n";
EOF

  # wartezimmer.php (mit "Boot self-heal reload" — das ist der Kernfix von 1.3.6)
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
      left: 0; right: 0; bottom: 0;
      padding: 10px 14px;
      font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif;
      font-size: 18px;
      color: rgba(255,255,255,0.90);
      text-align: center;
      background: rgba(0,0,0,0.35);
      text-shadow: 0 1px 2px rgba(0,0,0,0.7);
      pointer-events: none;
      display: none; /* nur bei Meldung */
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

  // audio config
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

  // audio ducking restore
  let savedVideoMuted = true;
  let savedVideoVolume = 0.0;

  // ---- Boot-self-heal: if nothing plays after boot, we reload (replaces manual F5) ----
  let bootOk = false;
  let bootStartTs = Date.now();
  let bootReloads = 0;

  function clamp01(x) {
    const n = Number(x);
    if (!isFinite(n)) return 0;
    return Math.max(0, Math.min(1, n));
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
    for (let i = 0; i < 90; i++) { // bis ~90s
      const files = await listMedia(kind);
      if (files.length > 0) return files;
      await new Promise(res => setTimeout(res, 1000));
    }
    return [];
  }

  function clearStage() {
    stage.innerHTML = "";
    videoEl = null;
    imgEl = null;
    if (videoWatchdog) { clearInterval(videoWatchdog); videoWatchdog = null; }
  }

  function applyVideoAudioFromConfig() {
    if (!videoEl) return;
    videoEl.muted = !videoSoundEnabled;
    videoEl.volume = videoSoundEnabled ? videoVolume : 0.0;
  }

  async function tryPlayVideo() {
    if (!videoEl) return false;
    try {
      applyVideoAudioFromConfig();
      const p = videoEl.play();
      if (p && typeof p.then === 'function') await p;
      return true;
    } catch (e) {
      return false;
    }
  }

  function nextIndex() {
    if (playlist.length === 0) return 0;
    return (idx + 1) % playlist.length;
  }

  function videoSrcForIndex(i) {
    idx = (playlist.length === 0) ? 0 : (i % playlist.length);
    return \`videos/\${encodeURIComponent(playlist[idx])}\`;
  }

  async function skipVideo() {
    if (!videoEl || playlist.length === 0) return;
    videoEl.src = videoSrcForIndex(nextIndex());
    await tryPlayVideo();
  }

  function attachVideoSelfHeal() {
    if (!videoEl) return;

    videoEl.addEventListener('error', () => { skipVideo(); });
    videoEl.addEventListener('ended', () => { skipVideo(); });

    // mark boot OK when we actually play/advance
    const markOk = () => {
      bootOk = true;
    };
    videoEl.addEventListener('playing', markOk);
    videoEl.addEventListener('timeupdate', markOk);
    videoEl.addEventListener('canplay', () => { /* not sufficient alone */ });

    // Watchdog: retry play/skip; if still not ok after boot window -> reload
    let lastOk = Date.now();
    const ping = () => { lastOk = Date.now(); };

    videoEl.addEventListener('playing', ping);
    videoEl.addEventListener('timeupdate', ping);

    videoWatchdog = setInterval(async () => {
      if (pausedByCall) return;
      if (!videoEl) return;

      const age = Date.now() - lastOk;

      // If we're not progressing: try play, then skip
      if (age > 2500) {
        const ok = await tryPlayVideo();
        if (!ok) await skipVideo();
      }

      // Boot self-heal:
      // If after 12s since boot start we still have not reached bootOk, reload (max 3x).
      const sinceBoot = Date.now() - bootStartTs;
      if (!bootOk && sinceBoot > 12000 && bootReloads < 3) {
        bootReloads += 1;
        // Backoff a bit to avoid reload storms
        setTimeout(() => location.reload(), 200 * bootReloads);
      }
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
      bootOk = true; // slideshow counts as "ok"
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

      if (mode === "slideshow") {
        await startSlideshowMode();
      } else {
        await startVideoMode();
      }
    } finally {
      starting = false;
    }
  }

  function duckVideoAudioForCall() {
    if (!videoEl) return;
    savedVideoMuted = !!videoEl.muted;
    savedVideoVolume = (typeof videoEl.volume === 'number') ? videoEl.volume : 0.0;
    videoEl.muted = true;
    videoEl.volume = 0.0;
  }

  function restoreVideoAudioAfterCall() {
    if (!videoEl) return;
    videoEl.muted = savedVideoMuted;
    videoEl.volume = savedVideoVolume;
  }

  function pauseNormal() {
    pausedByCall = true;
    if (videoEl) {
      duckVideoAudioForCall();
      try { videoEl.pause(); } catch(e) {}
    }
  }

  async function resumeNormal() {
    pausedByCall = false;
    if (restartAfterCall) {
      await startNormalMode();
      return;
    }
    if (videoEl) {
      restoreVideoAudioAfterCall();
      applyVideoAudioFromConfig();
      await tryPlayVideo();
    }
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

  function showOverlay(text, target, source) {
    ovTitle.textContent = text || "Aufruf";
    ovTarget.textContent = target || "";
    ovSource.textContent = source || "";
    overlay.style.display = "flex";
    footer.style.display = "block";
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

  // config reload
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

  # README
  cat >"${WEBROOT_DIR}/README_WARTEZIMMER.txt" <<EOF
${APP_NAME} v${VERSION}

Startseite:
- http://<pi-ip>/wartezimmer.php
- Kiosk lokal: http://127.0.0.1/wartezimmer.php

Konfiguration:
- ${CONFIG_JSON}

GDT-Quellen / Fetch (Sprechzimmer 1–2)
- Standard-Konzept: Der Wartezimmerbildschirm (Raspberry Pi) holt die Aufrufdateien per HTTP (Pull).
  Das ist die sauberste und sicherste Variante, da der Wartezimmerbildschirm ueber fragebogenpi vollstaendig vom Praxisnetz abgeschirmt ist.

Empfohlene URLs (Beispiel)
- Sprechzimmer 1:
  - GDT abrufen:   http://fragebogenpi.local/sprechzimmer1.gdt
  - GDT loeschen:  http://fragebogenpi.local/loesche-sprechzimmer1.php
- Sprechzimmer 2:
  - GDT abrufen:   http://fragebogenpi.local/sprechzimmer2.gdt
  - GDT loeschen:  http://fragebogenpi.local/loesche-sprechzimmer2.php

Alternative: Schreiben per SMB
- smb://wartezimmer/webroot  (Dateinamen: sprechzimmer1.gdt / sprechzimmer2.gdt)

Name-Format (optional)
- wartezimmer.json -> name_format.enabled=true
  Beispiel: letters 1 / 3 + dot=true -> "T. Kie."
  Leerzeichen und Bindestriche werden beim Zaehlen ignoriert.

Audio:
- Default chime: sounds/jsbach.m4a (Installer bootstrapped)
- getrennte Volumes: audio.video_volume / audio.chime_volume

Firewall:
- eth0 offen
- wlan0 inbound blockiert (nur established/related, DHCP, Ping)
EOF
}

configure_permissions_and_samba_ready() {
  say "Rechte: SMB-Guest RW wie besprochen"
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
  say "Samba: Guest RW Share auf /var/www/html"
  backup_file /etc/samba/smb.conf

  cat >/etc/samba/smb.conf <<EOF
[global]
   workgroup = WORKGROUP
   server string = ${APP_NAME}
   server role = standalone server

   map to guest = Bad User
   guest account = ${INFODISPLAY_USER}

   logging = syslog
   log level = 0

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
  say "Backend (SSE + Fetch/Delete + Name-Format) installieren"

  cat >/usr/local/bin/infodisplay-backend.py <<'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import asyncio
import json
import os
import time
from typing import Any, Dict, List, Optional, Tuple
from aiohttp import web, ClientSession, ClientTimeout

WEBROOT = "/var/www/html"
CONFIG_PATH = os.path.join(WEBROOT, "wartezimmer.json")
DEFAULT_LOG_FILE = os.path.join(WEBROOT, "logs", "backend.log")

def ts() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")

class Logger:
    def __init__(self) -> None:
        self.enabled = False
        self.level = "error"
        self.sink = "file"
        self.log_file = DEFAULT_LOG_FILE
        self._fp = None

    def apply_config(self, cfg: Dict[str, Any]) -> None:
        lc = cfg.get("logging", {})
        if isinstance(lc, dict):
            self.enabled = bool(lc.get("enabled", False))
            self.level = str(lc.get("level", "error")).lower()
            self.sink = str(lc.get("sink", "file")).lower()
            self.log_file = str(lc.get("log_file", DEFAULT_LOG_FILE))
        if self._fp:
            try: self._fp.close()
            except Exception: pass
            self._fp = None
        if not self.enabled:
            return
        if self.sink == "file":
            try:
                os.makedirs(os.path.dirname(self.log_file), exist_ok=True)
                self._fp = open(self.log_file, "a", encoding="utf-8")
            except Exception:
                self.sink = "stdout"
                self._fp = None

    def _want(self, lvl: str) -> bool:
        order = {"error": 0, "warn": 1, "info": 2, "debug": 3}
        return order.get(lvl, 3) <= order.get(self.level, 0)

    def log(self, lvl: str, msg: str) -> None:
        if not self.enabled or not self._want(lvl):
            return
        line = f"{ts()} [{lvl.upper()}] {msg}\n"
        if self.sink == "stdout":
            try: print(line, end="", flush=True)
            except Exception: pass
        else:
            if self._fp:
                try:
                    self._fp.write(line)
                    self._fp.flush()
                except Exception:
                    pass

def parse_first_last_from_gdt(gdt_text: str) -> Tuple[str, str]:
    firstname = ""
    lastname = ""
    for raw in gdt_text.splitlines():
        line = raw.strip()
        if not line or len(line) < 7:
            continue
        if not (line[:3].isdigit() and line[3:7].isdigit()):
            continue
        field = line[3:7]
        value = line[7:].strip()
        if field == "3102" and value:
            firstname = value
        elif field == "3101" and value:
            lastname = value
        if firstname and lastname:
            break
    return firstname, lastname

def _take_letters_ignoring_separators(s: str, n: int) -> str:
    if n <= 0:
        return ""
    out = []
    count = 0
    for ch in s.strip():
        if ch in (" ", "\t", "-", "–", "—"):
            continue
        out.append(ch)
        count += 1
        if count >= n:
            break
    return "".join(out)

def format_name(first: str, last: str, cfg: Dict[str, Any]) -> str:
    nf = cfg.get("name_format", {})
    if not isinstance(nf, dict) or not bool(nf.get("enabled", False)):
        full = (first + " " + last).strip()
        return full if full else "Aufruf"

    fnc = nf.get("first_name", {}) if isinstance(nf.get("first_name", {}), dict) else {}
    lnc = nf.get("last_name", {}) if isinstance(nf.get("last_name", {}), dict) else {}

    first_part = ""
    if first.strip() and bool(fnc.get("enabled", True)):
        letters = int(fnc.get("letters", 1) or 1)
        dot = bool(fnc.get("dot", True))
        first_part = _take_letters_ignoring_separators(first, max(1, letters))
        if dot and first_part:
            first_part += "."

    last_part = ""
    if last.strip() and bool(lnc.get("enabled", True)):
        letters = int(lnc.get("letters", 3) or 3)
        dot = bool(lnc.get("dot", True))
        last_part = _take_letters_ignoring_separators(last, max(1, letters))
        if dot and last_part:
            last_part += "."

    out = (first_part + " " + last_part).strip()
    return out if out else "Aufruf"

class EventHub:
    def __init__(self) -> None:
        self._clients: List[asyncio.Queue] = []
    def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=200)
        self._clients.append(q)
        return q
    def unsubscribe(self, q: asyncio.Queue) -> None:
        try: self._clients.remove(q)
        except ValueError: pass
    async def publish(self, payload: Dict[str, Any]) -> None:
        dead: List[asyncio.Queue] = []
        for q in self._clients:
            try: q.put_nowait(payload)
            except asyncio.QueueFull: dead.append(q)
        for q in dead: self.unsubscribe(q)

async def load_config(log: Logger) -> Optional[Dict[str, Any]]:
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        return cfg if isinstance(cfg, dict) else None
    except Exception as e:
        log.log("error", f"Config load failed: {e}")
        return None

async def sse_events(request: web.Request) -> web.StreamResponse:
    hub: EventHub = request.app["hub"]
    log: Logger = request.app["log"]
    q = hub.subscribe()

    resp = web.StreamResponse(status=200, headers={
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
        "Access-Control-Allow-Origin": "*",
    })
    await resp.prepare(request)

    async def heartbeat() -> None:
        while True:
            try: await resp.write(b": ping\n\n")
            except Exception: break
            await asyncio.sleep(10)

    hb_task = asyncio.create_task(heartbeat())

    try:
        while True:
            payload = await q.get()
            data = json.dumps(payload, ensure_ascii=False)
            await resp.write(f"data: {data}\n\n".encode("utf-8"))
    except Exception as e:
        log.log("warn", f"SSE client disconnected: {e}")
    finally:
        hb_task.cancel()
        hub.unsubscribe(q)
    return resp

async def fetch_gdt(session: ClientSession, url: str, log: Logger) -> Optional[str]:
    try:
        async with session.get(url) as r:
            if r.status == 204: return None
            if r.status != 200: return None
            txt = await r.text()
            return txt if txt.strip() else None
    except Exception as e:
        log.log("warn", f"fetch error {url}: {e}")
        return None

async def call_delete(session: ClientSession, url: str, log: Logger) -> bool:
    try:
        async with session.get(url) as r:
            return r.status in (200, 204)
    except Exception as e:
        log.log("warn", f"delete error {url}: {e}")
        return False

async def poll_loop(app: web.Application) -> None:
    hub: EventHub = app["hub"]
    log: Logger = app["log"]
    timeout = ClientTimeout(total=3.0)

    while True:
        cfg = await load_config(log)
        if cfg is None:
            await asyncio.sleep(2.0)
            continue

        log.apply_config(cfg)

        fetch_cfg = cfg.get("fetch", {}) if isinstance(cfg.get("fetch", {}), dict) else {}
        enabled = bool(fetch_cfg.get("enabled", False))
        poll_ms = int(fetch_cfg.get("poll_interval_ms", 500))
        max_jobs = int(fetch_cfg.get("max_jobs_per_room_per_cycle", 10))
        rooms = fetch_cfg.get("rooms", []) if isinstance(fetch_cfg.get("rooms", []), list) else []

        sound_dir = str(cfg.get("sound_dir", "sounds")).strip() or "sounds"
        default_sound = str(cfg.get("default_sound", "jsbach.m4a")).strip() or "jsbach.m4a"
        display_seconds = int(cfg.get("display_seconds", 10))

        if not enabled or not rooms:
            await asyncio.sleep(1.0)
            continue

        async with ClientSession(timeout=timeout) as session:
            for room in rooms:
                if not isinstance(room, dict): continue
                if not bool(room.get("enabled", True)): continue

                rid = str(room.get("id", "room")).strip() or "room"
                target = str(room.get("target", "")).strip()
                fetch_url = str(room.get("fetch_url", "")).strip()
                delete_url = str(room.get("delete_url", "")).strip()
                if not fetch_url or not delete_url: continue

                sound = f"{sound_dir}/{default_sound}"
                so = room.get("sound_override")
                if isinstance(so, str) and so.strip():
                    sound = so.strip() if "/" in so.strip() else f"{sound_dir}/{so.strip()}"

                jobs_done = 0
                while jobs_done < max_jobs:
                    gdt_text = await fetch_gdt(session, fetch_url, log)
                    if gdt_text is None:
                        break

                    first, last = parse_first_last_from_gdt(gdt_text)
                    name = format_name(first, last, cfg)

                    payload = {
                        "type": "call",
                        "source_id": rid,
                        "target": target,
                        "display_text": name,
                        "sound": sound,
                        "display_seconds": display_seconds,
                    }
                    await hub.publish(payload)

                    ok = await call_delete(session, delete_url, log)
                    if not ok:
                        await asyncio.sleep(2.0)
                        break

                    jobs_done += 1

                await asyncio.sleep(0.05)

        await asyncio.sleep(max(0.1, poll_ms / 1000.0))

async def on_startup(app: web.Application) -> None:
    app["poll_task"] = asyncio.create_task(poll_loop(app))

async def on_cleanup(app: web.Application) -> None:
    t = app.get("poll_task")
    if t:
        t.cancel()
        try: await t
        except Exception: pass

def main() -> None:
    log = Logger()
    try:
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            if isinstance(cfg, dict):
                log.apply_config(cfg)
    except Exception:
        pass

    app = web.Application()
    app["hub"] = EventHub()
    app["log"] = log

    app.router.add_get("/events", sse_events)
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)

    web.run_app(app, host="127.0.0.1", port=8765, access_log=None)

if __name__ == "__main__":
    main()
EOF

  chmod +x /usr/local/bin/infodisplay-backend.py

  cat >/etc/systemd/system/infodisplay-backend.service <<'EOF'
[Unit]
Description=fragebogenpi wartezimmerbildschirm backend (SSE + GDT fetch/delete)
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

configure_tmpfiles_for_chrome() {
  say "tmpfiles.d: RAM-Verzeichnisse für Chromium unter /run"
  cat >/etc/tmpfiles.d/wartezimmer.conf <<EOF
d ${RUN_CHROME_DIR} 0755 ${KIOSK_USER} ${KIOSK_USER} -
EOF
  systemd-tmpfiles --create /etc/tmpfiles.d/wartezimmer.conf >/dev/null 2>&1 || true
}

configure_kiosk_like_132() {
  say "Kiosk (wie 1.3.2): Chromium direkt starten (ohne wmctrl/xdotool), DPMS aus, Anti-throttle Flags"

  ensure_kiosk_user

  mkdir -p /etc/lightdm/lightdm.conf.d
  cat >/etc/lightdm/lightdm.conf.d/50-wartezimmer.conf <<EOF
[Seat:*]
autologin-user=${KIOSK_USER}
autologin-user-timeout=0
user-session=openbox
EOF

  mkdir -p "${KIOSK_HOME}/.config/openbox"
  chown -R "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/.config"

  local chrome_cmd="chromium"
  command -v chromium-browser >/dev/null 2>&1 && chrome_cmd="chromium-browser" || true
  command -v chromium >/dev/null 2>&1 && chrome_cmd="chromium" || true

  cat >"${KIOSK_HOME}/.config/openbox/autostart" <<EOF
unclutter -idle 0.5 -root &

# DPMS/Screensaver aus
xset s off
xset s noblank
xset -dpms

mkdir -p "${RUN_CHROME_DIR}"

# Warte bis lokaler Webserver da ist (konservativ)
for i in \$(seq 1 240); do
  if curl -fsS "http://127.0.0.1/wartezimmer.php" >/dev/null 2>&1 && \
     curl -fsS "http://127.0.0.1/wartezimmer.json" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

${chrome_cmd} \\
  --kiosk \\
  --noerrdialogs \\
  --disable-infobars \\
  --disable-session-crashed-bubble \\
  --autoplay-policy=no-user-gesture-required \\
  --lang=de-DE \\
  --disable-background-timer-throttling \\
  --disable-renderer-backgrounding \\
  --disable-backgrounding-occluded-windows \\
  --user-data-dir="${RUN_CHROME_DIR}/profile" \\
  --disk-cache-dir="${RUN_CHROME_DIR}/cache" \\
  --disable-pinch \\
  --overscroll-history-navigation=0 \\
  "http://127.0.0.1/wartezimmer.php" &
EOF

  chown "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/.config/openbox/autostart"
  chmod 0755 "${KIOSK_HOME}/.config/openbox/autostart"

  systemctl set-default graphical.target
  systemctl enable lightdm
}

configure_permissions_and_samba_ready() {
  say "Rechte (Webroot) setzen"
  ensure_group "$INFODISPLAY_GROUP"
  ensure_user_infodisplay
  usermod -a -G "$INFODISPLAY_GROUP" "$INFODISPLAY_USER" >/dev/null 2>&1 || true
  usermod -a -G "$INFODISPLAY_GROUP" "www-data" >/dev/null 2>&1 || true

  chown -R "${INFODISPLAY_USER}:${INFODISPLAY_GROUP}" "${WEBROOT_DIR}"
  chmod 2775 "${WEBROOT_DIR}"
  find "${WEBROOT_DIR}" -type d -exec chmod 2775 {} \;
  find "${WEBROOT_DIR}" -type f -exec chmod 0664 {} \;
}

main() {
  need_root
  say "${APP_NAME} — Installer v${VERSION}"

  apt_install

  ensure_group "$INFODISPLAY_GROUP"
  ensure_user_infodisplay

  ask_hostname_and_set_robust
  ask_wlan_enable_and_configure || true

  configure_firewall_wlan_only
  configure_chromium_policy

  install_webroot_files
  configure_permissions_and_samba_ready
  configure_apache_open_lan
  configure_samba

  install_backend
  configure_tmpfiles_for_chrome
  configure_kiosk_like_132

  say "Fertig. Reboot empfohlen."
  echo
  echo "Hinweis (1.3.6): Boot-Video-Fix passiert jetzt in der Web-App selbst (watchdog reload),"
  echo "kein wmctrl/xdotool mehr."
}

main "$@"
