#!/usr/bin/env bash
# Install webcam-ipu6 tools
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Installing webcam-ipu6 tools ==="

# Check for root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Get the actual user (not root)
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

echo "Installing for user: $REAL_USER"

# Install dependencies
echo "Installing dependencies..."
apt-get update
apt-get install -y v4l2loopback-dkms gstreamer1.0-libcamera gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good ffmpeg v4l-utils

# Copy system files
echo "Installing system files..."
install -m 755 "$SCRIPT_DIR/bin/webcam-bridge-run.system" /usr/local/bin/webcam-bridge-run
install -m 755 "$SCRIPT_DIR/bin/webcam-bridge-sleep" /usr/local/bin/webcam-bridge-sleep
install -m 644 "$SCRIPT_DIR/etc/systemd/system/webcam-bridge.service" /etc/systemd/system/
install -m 644 "$SCRIPT_DIR/etc/systemd/system/webcam-bridge-resume.service" /etc/systemd/system/
# Suspend/hibernate hook: stops the bridge on the way down, restarts it on resume.
install -d -m 755 /usr/lib/systemd/system-sleep
install -m 755 "$SCRIPT_DIR/etc/systemd/system-sleep/webcam-bridge" /usr/lib/systemd/system-sleep/webcam-bridge
install -m 644 "$SCRIPT_DIR/etc/modprobe.d/v4l2loopback.conf" /etc/modprobe.d/
install -m 644 "$SCRIPT_DIR/etc/udev/rules.d/99-v4l2loopback.rules" /etc/udev/rules.d/
install -m 644 "$SCRIPT_DIR/etc/udev/rules.d/99-webcam-symlink.rules" /etc/udev/rules.d/
install -m 644 "$SCRIPT_DIR/etc/udev/rules.d/60-webcam-hide-ipu6.rules.disabled" /etc/udev/rules.d/

# Create modules-load config
echo "v4l2loopback" > /etc/modules-load.d/v4l2loopback.conf

# Reload systemd and udev
systemctl daemon-reload
udevadm control --reload-rules

# Load module now
modprobe v4l2loopback devices=1 video_nr=42 card_label="Integrated Webcam" exclusive_caps=1 || true
udevadm trigger --subsystem-match=video4linux

# Install user scripts
echo "Installing user scripts to $REAL_HOME/.local/bin/..."
sudo -u "$REAL_USER" mkdir -p "$REAL_HOME/.local/bin"
sudo -u "$REAL_USER" install -m 755 "$SCRIPT_DIR/bin/webcam" "$REAL_HOME/.local/bin/"
sudo -u "$REAL_USER" install -m 755 "$SCRIPT_DIR/bin/webcam-bridge" "$REAL_HOME/.local/bin/"

# Install zsh completions
if [[ -d "$REAL_HOME/.zsh" ]] || command -v zsh &>/dev/null; then
    echo "Installing zsh completions..."
    sudo -u "$REAL_USER" mkdir -p "$REAL_HOME/.zsh/completions"
    sudo -u "$REAL_USER" install -m 644 "$SCRIPT_DIR/docs/_webcam" "$REAL_HOME/.zsh/completions/"
    sudo -u "$REAL_USER" install -m 644 "$SCRIPT_DIR/docs/_webcam-bridge" "$REAL_HOME/.zsh/completions/"

    # Add to fpath if not already there
    if ! grep -q 'fpath.*zsh/completions' "$REAL_HOME/.zshrc" 2>/dev/null; then
        echo 'fpath=(~/.zsh/completions $fpath)' >> "$REAL_HOME/.zshrc"
        echo "Added completions to .zshrc"
    fi
fi

# Check PATH
if [[ ":$PATH:" != *":$REAL_HOME/.local/bin:"* ]]; then
    echo ""
    echo "NOTE: Add ~/.local/bin to your PATH:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "=== Installation complete! ==="
echo ""
echo "Usage:"
echo "  webcam-bridge start          # Start bridge for Chrome/VLC/Zoom"
echo "  webcam-bridge --dark start   # Start with dark room preset"
echo "  webcam-bridge exclusive on   # Start with Firefox support"
echo "  webcam-bridge stop           # Stop bridge"
echo ""
echo "  webcam snap photo.jpg        # Take a photo directly"
echo "  webcam preview               # Live preview"
echo ""
echo "Device available at: /dev/webcam (symlink to /dev/video42)"
echo ""
echo "Reload your shell or run: source ~/.zshrc"
