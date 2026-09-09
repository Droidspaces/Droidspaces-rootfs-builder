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
