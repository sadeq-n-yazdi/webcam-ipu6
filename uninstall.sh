#!/usr/bin/env bash
# Uninstall webcam-ipu6 tools
set -euo pipefail

echo "=== Uninstalling webcam-ipu6 tools ==="

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Stop any running bridge
systemctl stop webcam-bridge.service 2>/dev/null || true
sudo -u "$REAL_USER" "$REAL_HOME/.local/bin/webcam-bridge" stop 2>/dev/null || true

# Remove system files
echo "Removing system files..."
rm -f /usr/local/bin/webcam-bridge-run
rm -f /usr/local/bin/webcam-bridge-sleep
rm -f /etc/systemd/system/webcam-bridge.service
rm -f /etc/systemd/system/webcam-bridge-resume.service
rm -f /usr/lib/systemd/system-sleep/webcam-bridge
rm -rf /run/webcam-bridge
rm -f /etc/modprobe.d/v4l2loopback.conf
rm -f /etc/modules-load.d/v4l2loopback.conf
rm -f /etc/udev/rules.d/99-v4l2loopback.rules
rm -f /etc/udev/rules.d/99-webcam-symlink.rules
rm -f /etc/udev/rules.d/60-webcam-hide-ipu6.rules
rm -f /etc/udev/rules.d/60-webcam-hide-ipu6.rules.disabled

# Reload
systemctl daemon-reload
udevadm control --reload-rules

# Unload module
rmmod v4l2loopback 2>/dev/null || true

# Remove user scripts
echo "Removing user scripts..."
rm -f "$REAL_HOME/.local/bin/webcam"
rm -f "$REAL_HOME/.local/bin/webcam-bridge"
rm -f "$REAL_HOME/.zsh/completions/_webcam"
rm -f "$REAL_HOME/.zsh/completions/_webcam-bridge"

echo ""
echo "=== Uninstall complete ==="
echo "Note: v4l2loopback-dkms package was not removed. Run:"
echo "  sudo apt remove v4l2loopback-dkms"
