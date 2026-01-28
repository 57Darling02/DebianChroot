# DebianChroot Magisk Module

A Magisk module that deploys a full Debian Bookworm rootfs on your Android device, complete with Runit service management and a powerful helper tool (`lm`).

## Features

- **Full Debian 12 (Bookworm)**: Runs a complete Debian environment alongside Android.
- **Runit Service Management**: Integrated `runit` init system for managing background services.
- **Seamless Integration**:
  - Automatically mounts Android's `/dev`, `/proc`, `/sys`, `/system`, `/data`, and `/sdcard`.
  - Fixes network permissions and Android-specific GIDs.
- **Linux Manager (`lm`)**: A built-in helper tool to easily manage your container:
  - **One-click Mirror Switch**: Switch to faster local mirrors (via LinuxMirrors).
  - **SSH Server Setup**: Easily configure and start SSH service.
  - **TMOE Integration**: Launch TMOE tools for advanced management.
  - **Systemd Emulation**: Includes `servicectl` for systemd-like service control.

## Installation

1. Download the latest release zip file.
2. Install the module via Magisk Manager or KernelSU.
3. Reboot your device.

## Usage

### Entering the Container

You can access the Debian shell via a terminal emulator (like Termux) or ADB.

1. Open your terminal.
2. Switch to root:
   ```bash
   su
   ```
3. Run the start script:
   ```bash
   /data/adb/modules/DebianChroot/scripts/start.sh
   ```
   *(This script will start the container services if they aren't running, and then drop you into a shell.)*

### Managing the Container (`lm`)

Once inside the container, simply type `lm` to open the management menu:

```bash
root@localhost:~# lm
```

From here you can:
- Install basic dependencies.
- Change software sources mirrors.
- Configure SSH (port, password, pubkey).
- Start TMOE tools.
- Fix/Setup service controls.

### Service Management

The container uses **Runit** as the init system. Services are located in `/etc/service`.

- **Check status**: `sv status <service_name>`
- **Start/Stop**: `sv start <service_name>` / `sv stop <service_name>`

You can also use the built-in `servicectl` wrapper (configured via `lm`) for a systemd-like experience:
```bash
servicectl start <service>
servicectl status <service>
```

## Build & Release

This project includes a GitHub Actions workflow for automatic releases.

1. Fork/Clone this repository.
2. Update `version` and `versionCode` in `module.prop`.
3. Commit and push your changes to GitHub.
4. The workflow will automatically build the zip and create a new Release.

> **Note**: Ensure "Read and write permissions" are enabled in your repository settings (Settings -> Actions -> General -> Workflow permissions).

## Credits

- **Debian**: For the solid operating system.
- **Magisk**: For the module system.
- **BusyBox**: For essential utilities.
- **TMOE/LinuxMirrors**: For the awesome helper scripts.
