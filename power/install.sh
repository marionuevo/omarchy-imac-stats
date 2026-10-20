#!/bin/sh
# Install the power-profile limits. Run with sudo from the plugin directory:
#   sudo ./power/install.sh
set -e
cd "$(dirname "$0")"

[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }

install -m 0755 imac-power-profile /usr/local/bin/imac-power-profile
install -m 0644 imac-power-profile.service imac-power-profile.path /etc/systemd/system/

systemctl daemon-reload
# reenable drops a multi-user.target link left by earlier versions.
systemctl reenable imac-power-profile.service
systemctl enable --now imac-power-profile.path
systemctl start imac-power-profile.service
journalctl -t imac-power-profile -n 1 --no-pager
