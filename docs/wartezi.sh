#!/usr/bin/env bash
set -euo pipefail

REAL_INSTALLER_URL="https://raw.githubusercontent.com/thomaskien/fragebogenpi/main/wartezimmer.sh"

echo "FragebogenPi Installer"
echo "Quelle: $REAL_INSTALLER_URL"
echo
echo "Lade Installationsskript…"
echo

rm -f fragebogenpi.sh
wget "$REAL_INSTALLER_URL" 
chmod +x wartezimmer.sh
./wartezimmer.sh
