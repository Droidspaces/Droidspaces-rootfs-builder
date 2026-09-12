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

GUI templates (`*-XFCE`, `*-bspwm`) ship a systemd service that autostarts the
desktop on the Termux:X11 display once the container reaches `graphical.target`. The service
runs as root and drops to a **desktop user** before launching the session.

- XFCE templates read **`XFCE_USER`** from `/run/droidspaces.env` (written by the host app).
- bspwm templates read **`DESKTOP_USER`** the same way. Default (unset or `root`) runs
  the desktop as root. On `Arch-bspwm-Kernel-5.10-and-up` a non-root `DESKTOP_USER` must be
  added to `aid_inet,aid_net_raw,input,video,tty` by hand - Arch's `useradd` has no
  supplementary-group default to hook, unlike Debian's `adduser.conf`.

The bspwm templates (`Ubuntu-24.04-bspwm`, `Arch-bspwm-Kernel-5.10-and-up`) are XFCE's package
set with the desktop swapped for the bspwm tiling WM plus a touch-friendly Catppuccin theme
(polybar bar + dock, rofi menus, PulseAudio Volume Control, dynamic desktops, drag-to-resize,
a settings hub). The theme lives in
`scripts/bspwm/bspwm-theme/` and is seeded three ways so **every** user gets it by default: a
read-only master at `/usr/share/droidspaces/bspwm-theme`, a build-time copy into `/root` and
`/etc/skel`, and a runtime seed in `bspwm-start` for any user created without skel. The same
`scripts/bspwm/bspwm-theme` payload is published as a standalone importer for raw bspwm installs.
