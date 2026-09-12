# Droidspaces RootFS Builder

Builds rootfs tarballs for [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) from Dockerfiles,
publishes them as GitHub releases, and regenerates `rootfs.json` on every release.

## Layout

```
archs.json                  supported architectures -> docker platform + CI runner
build.sh                    builds one template for one arch
templates/<arch>/<Name>.Dockerfile
scripts/generate_rootfs_json.py
rootfs.json                 generated, do not edit by hand
```

## Adding a distro

Create `templates/<arch>/<Name>.Dockerfile`. That is the whole change.

The Dockerfile must end with an `export` stage carrying the metadata labels:

```dockerfile
FROM scratch AS export
LABEL droidspaces.name="Ubuntu 24.04 LTS - Minimal" \
      droidspaces.distro="Ubuntu" \
      droidspaces.description="Minimal Ubuntu 24.04 rootfs with basic packages." \
      droidspaces.author="Droidspaces developers"
COPY --from=customizer / /
```

`name`, `distro`, and `description` are required. `author` defaults to "Droidspaces developers".
Any extra `droidspaces.<key>` label is copied into the `rootfs.json` entry as `<key>`.

Build context is the repo root, so `COPY scripts/...` works from any template.

## Adding an architecture

Add a key to `archs.json` and create `templates/<arch>/`.

## Building locally

```sh
./build.sh -a aarch64 -i Ubuntu-24.04-Minimal
```

Needs docker with buildx, jq, and xz. QEMU is registered automatically when the host
cannot run the target platform natively.

## Checking labels

```sh
python3 scripts/generate_rootfs_json.py --lint
```

## CI

`.github/workflows/build-rootfs-releases.yml` runs on push to `main`, weekly, or by hand.
It lints labels, builds every template in parallel on the runner for its arch, creates one
release with all tarballs, then regenerates and commits `rootfs.json`. Any failed build
blocks the release. The manual "update_json_only" input regenerates `rootfs.json` from the
current latest release without building.

## Desktop templates and the desktop user

GUI templates (`*-XFCE`, `*-bspwm`) autostart the desktop on the Termux:X11 display and run it
as **root** unless you name a desktop user. XFCE templates read `XFCE_USER`; bspwm templates
read `DESKTOP_USER`. Both come from `/run/droidspaces.env`, which the host app writes at start
(CLI: pass an env file with `droidspaces --env=PATH`).

### Creating the desktop user

Run these **inside the container**, as root.

Debian / Ubuntu / Kali:

```sh
adduser alice                     # home, groups and password in one step
usermod -aG sudo alice            # optional: sudo
```

Arch / Artix - `useradd` creates nothing by default, so pass all of it:

```sh
useradd -m -G wheel,aid_inet,aid_net_raw,input,video,tty alice
passwd alice
```

`-m` creates the home, `aid_inet,aid_net_raw` give network access on Android kernels, and
`input,video,tty` give hardware access. Skipping `-G` leaves the user with no network.

Optional, for `sudo pacman -Syu` from Settings > Update packages (Power off and Restart
already work without it):

```sh
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/11-wheel && chmod 440 /etc/sudoers.d/11-wheel
```

### Pointing the desktop at it

Set the variable in the host app's environment settings, then restart the container:

```sh
DESKTOP_USER=alice                # bspwm templates
XFCE_USER=alice                   # XFCE templates
```

The bspwm templates (`Ubuntu-24.04-bspwm`, `Arch-bspwm-Kernel-5.10-and-up`,
`Artix-bspwm-OpenRC`) are XFCE's package
set with the desktop swapped for the bspwm tiling WM plus a touch-friendly Catppuccin theme
(polybar bar + dock, rofi menus, PulseAudio Volume Control, dynamic desktops, drag-to-resize,
a settings hub). The theme lives in
`scripts/bspwm/bspwm-theme/` and is seeded three ways so **every** user gets it by default: a
read-only master at `/usr/share/droidspaces/bspwm-theme`, a build-time copy into `/root` and
`/etc/skel`, and a runtime seed in `bspwm-start` for any user created without skel. The same
`scripts/bspwm/bspwm-theme` payload is published as a standalone importer for raw bspwm installs.

The theme itself is init- and distro-agnostic: it picks `pacman` or `apt`, reads the top-bar
logo from `os-release`, bundles its own fonts, and uses `poweroff`/`reboot` where there is no
`systemctl`. Only the autostart glue differs per template - a systemd unit on Ubuntu/Arch, an
OpenRC service driving `supervise-daemon` on Artix. Two packages have no Armtix equivalent, so
`Artix-bspwm-OpenRC` ships without the tap-the-clock calendar (`gsimplecal`) and without the
alternate cursor themes (`xcursor-themes`); the default Adwaita cursor is present.
