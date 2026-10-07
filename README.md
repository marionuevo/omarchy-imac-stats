# iMac Stats

[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE)
[![Omarchy](https://img.shields.io/badge/omarchy-shell%20plugin-1793d1)](https://omarchy.org)

A minimal `bar-widget` plugin for the [Omarchy](https://omarchy.org/) shell (Quickshell) on an Intel iMac, plus a small fan daemon. Shows fan RPM, CPU/GPU temp and usage, RAM and disk usage as a static row of icon+value pairs. Clicking opens a fan mode picker.

Built for an iMac15,1 (Retina 5K, late 2014: i5-4690, Radeon R9 M290X/M295X) and adapted from [omarchy-minimal-liquid-stats](https://github.com/marionuevo/omarchy-minimal-liquid-stats).

## Why a daemon

`mbpfan` only reads `coretemp`. A GPU-only load (a game, `glmark2`) heats the Radeon while the fan sits at its 1200 rpm floor. `imac-fand` takes **max(CPU, GPU)** every second and sets the SMC fan target from that.

It runs as a root systemd service, separate from the shell: if the bar or the whole desktop dies, the fan keeps being regulated. When the daemon stops, it hands the fan back to the SMC's automatic control (`fan1_manual = 0`); the unit's `ExecStopPost` does the same if the process is killed outright.

## Sensors

| Icon | Value | Source |
|------|-------|--------|
| 󰈐 fan | Fan RPM (`!` when the daemon is down) | `applesmc` `fan1_input` |
|  CPU | CPU temp / usage % | `coretemp` "Package id 0", `/proc/stat` |
| 󰢮 GPU | GPU temp / usage % | `amdgpu` "edge" (SMC `TG0D` as daemon fallback), `radeontop` |
| 󰍛 memory | RAM usage % | `/proc/meminfo` |
| 󰋊 disk | `/` usage % | `shutil.disk_usage` |

`gpu_busy_percent` is not implemented for this Southern Islands Radeon, so GPU usage comes from a one-second `radeontop` sample that overlaps the CPU sample.

`applesmc` registers no hwmon `name` file on this kernel, so the fan is found through `/sys/devices/platform/applesmc.*`.

## Fan modes

| Mode | Leaves 1200 rpm floor | Reaches 2700 rpm |
|------|-----------------------|------------------|
| **Silent** | 68°C | 90°C |
| **Normal** | 60°C | 85°C |
| **Full** | always max | |

The curve applies to the hotter of CPU and GPU. In every mode, 90°C or more means full speed, and so does losing both sensors. The Radeon idles around 55°C, so both knees sit above that. Ramp is up to +400 rpm per second, down at −40 rpm per second, so bursty loads don't make the fan hunt.

The mode lives in `/var/lib/imac-fan/mode`, the only file the desktop user may write; the daemon treats anything that isn't a known mode as `normal`. It survives reboots. The daemon publishes what it is doing in `/run/imac-fan/status.json`, which the widget reads.

## Installation

```sh
omarchy plugin add https://github.com/marionuevo/omarchy-imac-stats.git --enable
omarchy bar put marionuevo.imac-stats --section left
sudo ~/.config/omarchy/plugins/marionuevo.imac-stats/daemon/install.sh
```

`install.sh` disables `mbpfan`, installs `imac-fand` to `/usr/local/bin`, the unit to `/etc/systemd/system`, gives the mode file to the user who ran `sudo`, and starts the service. The unit also `Conflicts=mbpfan.service`, so the two can never fight over the fan.

```sh
systemctl status imac-fand
cat /run/imac-fan/status.json
```

## Requirements

- Omarchy running on Hyprland
- Python 3
- `applesmc` and `coretemp` (loaded by default on Intel Macs), `amdgpu`
- `radeontop` for GPU usage (optional; shows `--%` without it)
