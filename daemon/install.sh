#!/bin/sh
# Replace mbpfan with imac-fand. Run with sudo from the plugin directory:
#   sudo ./daemon/install.sh
set -e
cd "$(dirname "$0")"

[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
OWNER="${SUDO_UID:-1000}"

systemctl disable --now mbpfan.service 2>/dev/null || true

install -m 0755 imac-fand /usr/local/bin/imac-fand
install -m 0644 imac-fand.service /etc/systemd/system/imac-fand.service

# The mode file is the only thing the desktop user can change: the plugin
# writes one word into it and the daemon ignores anything else.
install -d -m 0755 /var/lib/imac-fan
[ -f /var/lib/imac-fan/mode ] || echo normal > /var/lib/imac-fan/mode
chown "$OWNER" /var/lib/imac-fan/mode
chmod 0644 /var/lib/imac-fan/mode

systemctl daemon-reload
systemctl enable --now imac-fand.service
systemctl --no-pager status imac-fand.service | head -5
