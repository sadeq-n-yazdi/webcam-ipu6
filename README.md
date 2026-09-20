# Webcam Bridge for Intel IPU6 Cameras

Tools for using Intel IPU6 MIPI cameras (like the OmniVision OV2740 in ThinkPad X1 Carbon Gen 10) with standard V4L2 applications like Chrome, Firefox, VLC, Zoom, and OBS.

## The Problem

Intel IPU6 cameras don't appear as standard `/dev/video0` devices. They use libcamera through PipeWire, which most applications don't support natively. This toolkit bridges the gap by feeding the tuned camera stream into a v4l2loopback device that apps can use.

## Features

- **v4l2loopback bridge**: Makes the camera appear as `/dev/webcam` (symlink to `/dev/video42`)
- **Manual exposure control**: Prevents auto-exposure flickering with bright backlighting
- **Color correction**: Fixes the green cast common with IPU6 sensors
- **Exposure presets**: `--bright`, `--normal`, `--dark`, `--night` for different lighting
- **Firefox support**: Exclusive mode hides decoy IPU6 nodes that confuse Firefox
- **1080p @ 30fps**: Full HD output with hardware-accelerated color correction

## Requirements

- Linux with Intel IPU6 camera (tested on Ubuntu 24.04+)
- v4l2loopback-dkms
- GStreamer 1.x with libcamera plugin
- FFmpeg with v4l2 support
- PipeWire

## Installation

```bash
# Install dependencies
sudo apt install v4l2loopback-dkms gstreamer1.0-libcamera ffmpeg v4l-utils

# Clone and run installer
git clone https://github.com/YOUR_USERNAME/webcam-ipu6.git
cd webcam-ipu6
sudo ./install.sh
```

## Usage

### Start the bridge (for Chrome, VLC, Zoom, OBS)

```bash
webcam-bridge start           # Normal lighting
webcam-bridge --bright start  # Bright room
webcam-bridge --dark start    # Dim room
webcam-bridge --night start   # Very dark
webcam-bridge --auto start    # Auto-exposure (may flicker)

# Custom exposure
webcam-bridge --gain 6.0 --exposure 18000 start
```

### Stop the bridge

```bash
webcam-bridge stop
```

### Firefox support (exclusive mode)

Firefox gets confused by the 32 decoy IPU6 nodes. Exclusive mode hides them:

```bash
webcam-bridge exclusive on   # Start with Firefox support
webcam-bridge exclusive off  # Revert when done
```

### Direct capture (no bridge needed)

```bash
webcam snap photo.jpg        # Take a still
webcam record 10 video.mp4   # Record 10 seconds
webcam preview               # Live preview window
webcam info                  # Show device info
```

### Test with apps

```bash
vlc v4l2:///dev/webcam       # VLC
ffplay /dev/webcam           # FFmpeg
```

## Exposure Settings

| Preset    | Gain | Exposure (µs) | Use Case |
|-----------|------|---------------|----------|
| `--bright`| 2.0  | 8000          | Sunny room, bright lights |
| `--normal`| 4.0  | 15000         | Normal indoor lighting |
| `--dark`  | 8.0  | 25000         | Dim room, evening |
| `--night` | 12.0 | 33000         | Very dark, night |

## Keyboard Shortcut (F12 Toggle)

Set up a hotkey to toggle the webcam bridge on/off:

### GNOME (Ubuntu, Fedora)

1. Open **Settings** → **Keyboard** → **Keyboard Shortcuts** → **Custom Shortcuts**
2. Click **+** to add a new shortcut
3. Set:
   - **Name:** Toggle Webcam
   - **Command:** `~/.local/bin/webcam-toggle`
   - **Shortcut:** Press F12 (or your preferred key)

Or via command line:
```bash
# Create the custom shortcut
CUSTOM_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/webcam-toggle/"
gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_PATH" name "Toggle Webcam"
gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_PATH" command "$HOME/.local/bin/webcam-toggle"
gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_PATH" binding "F12"

# Add to the custom keybindings list
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$CUSTOM_PATH']"
```

### Other Desktop Environments

- **KDE:** System Settings → Shortcuts → Custom Shortcuts
- **XFCE:** Settings → Keyboard → Application Shortcuts
- **i3/sway:** Add to config: `bindsym F12 exec ~/.local/bin/webcam-toggle`

## Troubleshooting

### Camera not found after failed shutdown

The IPU6 firmware authenticates once per power cycle. If the bridge is killed improperly (not via `webcam-bridge stop`), the firmware wedges. **Only a reboot fixes this.**

Always use `webcam-bridge stop` or `systemctl stop webcam-bridge.service`.

### GNOME Snapshot shows black screen

Snapshot uses libcamera directly, conflicting with the bridge. Stop the bridge first:
```bash
webcam-bridge stop
```

### Flickering with auto-exposure

Use manual exposure presets instead of `--auto`. The bright window backlight confuses auto-exposure.

### Green tint

Color correction is applied automatically. If still green, adjust the CC filter:
```bash
export WEBCAM_CC="colorchannelmixer=rr=1.12:gg=0.94:bb=1.08,eq=contrast=1.06:saturation=1.10"
webcam-bridge start
```

## Files Installed

| File | Location | Purpose |
|------|----------|---------|
| `webcam` | `~/.local/bin/` | Direct capture tool |
| `webcam-bridge` | `~/.local/bin/` | Bridge control script |
| `webcam-bridge-run` | `/usr/local/bin/` | System service runner |
| `webcam-bridge.service` | `/etc/systemd/system/` | Systemd service |
| `v4l2loopback.conf` | `/etc/modprobe.d/` | Loopback module config |
| `99-v4l2loopback.rules` | `/etc/udev/rules.d/` | Device permissions |
| `99-webcam-symlink.rules` | `/etc/udev/rules.d/` | `/dev/webcam` symlink |
| `60-webcam-hide-ipu6.rules.disabled` | `/etc/udev/rules.d/` | Firefox exclusive mode |

## Tested Hardware

- ThinkPad X1 Carbon Gen 10 with OmniVision OV2740 sensor
- Ubuntu 24.04+ with kernel 6.x/7.x (including `-gke` variants)

## License

MIT License - feel free to use and modify.
