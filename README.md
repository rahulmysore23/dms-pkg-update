# DMS Package Updates

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) widget that checks for pending **system package** updates (**APT** or **DNF**), **Flatpak** updates, and **Snap** updates, then lets you run them directly from the bar.

![Screenshot](https://raw.githubusercontent.com/rahulmysore23/dms-pkg-update/main/screenshot.png)

## Features

- Shows total pending update count in the bar pill
- Lists available system package updates (APT/DNF) with version numbers
- Lists available Flatpak app updates with remote origin
- Lists available Snap updates with version numbers
- **Update Packages** button — opens a terminal and runs:
	- `sudo apt update && sudo apt upgrade -y` (APT backend)
	- `sudo dnf upgrade -y` (DNF backend)
- **Update Flatpak** button — opens a terminal and runs `flatpak update -y`
- **Update Snap** button — opens a terminal and runs `sudo snap refresh`
- Configurable refresh interval
- Configurable terminal application
- Configurable package backend mode (`auto`, `apt`, `dnf`)
- Shows actionable check errors (missing backend, apt refresh failure, Flatpak/Snap issues)
- APT metadata refresh for checks uses `aptdcon --refresh` (no `sudo` required)

## Installation

### From Plugin Registry (Recommended)

```bash
dms plugins install pkgUpdate
# or use the Plugins tab in DMS Settings
```

### Manual

```bash
cp -r pkgUpdate ~/.config/DankMaterialShell/plugins/
```

Then enable the widget in the DMS Plugins tab and add it to DankBar.

## Configuration

| Setting | Default | Description |
|---|---|---|
| Terminal Application | `alacritty` | Terminal command used to run updates (supports args like `kitty --single-instance`; unsafe shell tokens fallback to `alacritty`) |
| Refresh Interval | `60` min | How often to check for updates (5–240 min) |
| Package Backend | `auto` | System package backend: `auto` (prefer APT, fallback DNF), `apt`, or `dnf` (invalid values fallback to `auto`) |
| Show Flatpak Updates | `true` | Toggle Flatpak section on/off |
| Show Snap Updates | `true` | Toggle Snap section on/off |

## Requirements

- One system package manager:
	- `apt` (Ubuntu/Debian-based systems)
	- `dnf` (Fedora/RHEL-based systems)
- `aptdcon` (required when using `apt` backend for update checks)
- `flatpak` (optional, can be disabled in settings)
- `snap` (optional, can be disabled in settings)
- A terminal emulator that accepts `-e` to run a command

## License

MIT

