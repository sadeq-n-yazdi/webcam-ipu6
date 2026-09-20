# Technical Documentation: Intel IPU6 Webcam Bridge

## Architecture Overview

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐     ┌─────────────┐
│   OV2740/IPU6   │────▶│  libcamera   │────▶│   GStreamer     │────▶│  v4l2loopback│
│   MIPI Sensor   │     │   + ISP      │     │   + ffmpeg CC   │     │  /dev/video42│
└─────────────────┘     └──────────────┘     └─────────────────┘     └─────────────┘
                                                                            │
                                                      ┌─────────────────────┼─────────────────────┐
                                                      ▼                     ▼                     ▼
                                               ┌───────────┐         ┌───────────┐         ┌───────────┐
                                               │  Chrome   │         │    VLC    │         │   Zoom    │
                                               └───────────┘         └───────────┘         └───────────┘
```

## Why This Exists

Intel IPU6 cameras don't appear as standard `/dev/video0` V4L2 devices. They use:
- **MIPI CSI-2** interface (not USB)
- **libcamera** for capture (not V4L2)
- **PipeWire** for desktop integration

Most applications (Chrome, Zoom, VLC) expect a standard V4L2 capture device. This bridge:
1. Captures from libcamera
2. Applies color correction (fixes green tint)
3. Outputs to v4l2loopback as a standard V4L2 device

## The IPU6 Firmware Issue

**Critical:** The IPU6 firmware is authenticated **once per power cycle** by Intel's Converged Security Engine (CSE).

If the camera stream is not stopped cleanly:
1. The kernel logs `stream stop time out`
2. The CSE refuses to re-authenticate the firmware
3. The camera is **dead until reboot**

**The fix:** Always use `SIGINT` (not `SIGTERM`) to stop gst-launch-1.0. The systemd service is configured for this.

## Exposure Control

### The Problem
Auto-exposure (AE) oscillates wildly when there's a bright backlight (e.g., window behind user), causing extreme frame-to-frame brightness variation ("flickering").

### The Solution
Manual exposure with fixed values:
- `ae-enable=false` - Disable auto-exposure
- `analogue-gain-mode=1` - Manual gain mode
- `analogue-gain=4.0` - Gain multiplier (1.0-16.0)
- `exposure-time-mode=1` - Manual exposure mode
- `exposure-time=15000` - Exposure time in microseconds

### Presets
| Preset | Gain | Exposure (µs) | Use Case |
|--------|------|---------------|----------|
| bright | 2.0  | 8000          | Sunny, bright lights |
| normal | 4.0  | 15000         | Indoor, normal lighting |
| dark   | 8.0  | 25000         | Dim room, evening |
| night  | 12.0 | 33000         | Very dark |

## Color Correction

The IPU6 software ISP produces a ~8% green cast that libcamera's AWB cannot correct.

**FFmpeg filter applied:**
```
colorchannelmixer=rr=1.08:gg=0.96:bb=1.06,eq=contrast=1.06:saturation=1.10
```

This:
- Boosts red channel by 8%
- Reduces green channel by 4%
- Boosts blue channel by 6%
- Slightly increases contrast and saturation

Adjust via `WEBCAM_CC` environment variable if needed.

## Firefox Exclusive Mode

Firefox enumerates **33 V4L2 devices** (32 IPU6 ISYS decoys + 1 loopback) and collapses them all into one unusable device.

**Solution:** Hide the 32 decoy nodes with a udev rule:
```bash
webcam-bridge exclusive on
```

This:
1. Enables `/etc/udev/rules.d/60-webcam-hide-ipu6.rules`
2. Makes `/dev/video0-31` root-only
3. Runs the bridge as a system service
4. Firefox now sees only `/dev/video42`

## Suspend and Hibernate

Sleeping with the IPU6 stream open is the same failure as killing the pipeline hard:
`stream stop time out` in dmesg, wedged firmware, camera gone until a power cycle. The
bridge is therefore torn down before sleep and brought back after resume.

```
/usr/lib/systemd/system-sleep/webcam-bridge
  pre  -> /usr/local/bin/webcam-bridge-sleep pre        (synchronous, blocks the suspend)
  post -> systemctl start --no-block webcam-bridge-resume.service
                 -> /usr/local/bin/webcam-bridge-sleep resume
```

**Why resume goes through a unit instead of the hook.** Everything the `post` hook spawns
lives in `systemd-suspend.service`'s cgroup, which is reaped when that unit exits —
`setsid` does not escape it. A bridge started from the hook would be SIGKILLed moments
later, leaving the stream un-stopped: the exact wedge this whole design avoids.
`webcam-bridge-resume.service` gets its own cgroup and outlives the hook.

**State** is written to `/run/webcam-bridge/` (tmpfs: gone after a real boot, preserved
inside a hibernation image — both of which are the wanted behaviour):

| File | Contents |
|------|----------|
| `suspend-state` | One line per thing that was running: `service -` or `user <uid>` |
| `user-<uid>.env` | That user's `WEBCAM_GAIN`/`WEBCAM_EXPOSURE` at stop time, mode 0600 |

The env file sits in `/run/user/<uid>`, which its owner controls, so the hook treats it
as untrusted input. It is read with `runuser` as that user — a root-side `cp` would
follow a symlink planted there and copy, say, `/etc/shadow` into the state dir — and
filtered through an allowlist (`WEBCAM_GAIN`/`WEBCAM_EXPOSURE`, plain values only),
re-applied on resume because those words become argv for `env`. An unfiltered line
without an `=` would otherwise be run by `env` as the command instead of the bridge.
`/run/webcam-bridge` is mode 0700.

`webcam-bridge start` now writes `$XDG_RUNTIME_DIR/webcam-bridge.env` alongside its PID
file; resume feeds it back through the environment, so the restored stream has the same
exposure as before the sleep.

Details that matter:

- Teardown calls the user's own `webcam-bridge stop` via `runuser`, reusing the
  PGID + SIGINT + wait + escalation path rather than reimplementing it. It passes
  `WEBCAM_STOP_WAIT=30` (interactive default: 12): escalating to SIGKILL is exactly
  what produces `stream stop time out`, and `systemd-suspend.service` sets no start
  timeout, so patience costs nothing here.
- Exclusive mode is stopped with a plain `systemctl stop`, **not** `exclusive off` — the
  udev rule hiding the decoy nodes stays in place across the sleep.
- `pre` is idempotent and never clobbers existing state, so `suspend-then-hibernate`
  firing the hooks twice is harmless.
- `resume` polls `camera_healthy()` for up to 20s, then makes exactly one start attempt.
  No retry loop: repeatedly re-initialising wedged firmware makes it worse, and the
  "needs a reboot" message in the journal is the useful outcome.

Both halves can be exercised without suspending:

```bash
sudo /usr/local/bin/webcam-bridge-sleep pre
sudo /usr/local/bin/webcam-bridge-sleep resume
journalctl -b -u systemd-suspend.service -u webcam-bridge-resume.service
```

After a real suspend cycle the check that actually discriminates is
`dmesg | grep -i 'ipu6\|stream stop'` — no `stream stop time out` means the pre hook
finished before the kernel went down.

## File Locations

| File | Purpose |
|------|---------|
| `/usr/local/bin/webcam-bridge-run` | System service runner |
| `/usr/local/bin/webcam-bridge-sleep` | Suspend/resume handler |
| `/etc/systemd/system/webcam-bridge.service` | Systemd service |
| `/etc/systemd/system/webcam-bridge-resume.service` | Restarts the bridge after resume |
| `/usr/lib/systemd/system-sleep/webcam-bridge` | Sleep/wake hook |
| `/etc/modprobe.d/v4l2loopback.conf` | Module configuration |
| `/etc/udev/rules.d/99-v4l2loopback.rules` | Device permissions |
| `/etc/udev/rules.d/99-webcam-symlink.rules` | /dev/webcam symlink |
| `/etc/udev/rules.d/60-webcam-hide-ipu6.rules.disabled` | Firefox exclusive mode |
| `~/.local/bin/webcam` | User capture tool |
| `~/.local/bin/webcam-bridge` | User bridge control |
| `~/.local/bin/webcam-toggle` | Keyboard shortcut script |

## Troubleshooting

### Camera not found after crash
```
ERROR: the IPU6 camera hardware is not available.
```
**Solution:** Reboot. The firmware wedged.

### Green tint
Adjust color correction:
```bash
export WEBCAM_CC="colorchannelmixer=rr=1.12:gg=0.92:bb=1.10,eq=contrast=1.06:saturation=1.10"
webcam-bridge start
```

### Too dark / too bright
Use exposure presets or custom values:
```bash
webcam-bridge --dark start
webcam-bridge --gain 6.0 --exposure 20000 start
```

### Check camera health
```bash
# Verify kernel loaded drivers
sudo dmesg | grep -i "ipu6\|ov2740"

# Verify libcamera sees camera
gst-device-monitor-1.0 Video/Source | grep -A5 "Built-in"

# Test direct capture
webcam snap test.jpg
```
