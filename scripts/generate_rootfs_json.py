#!/usr/bin/env python3
"""
Generates rootfs.json from scratch.

Metadata comes from `LABEL droidspaces.*` in each templates/<arch>/<Name>.Dockerfile.
Download data comes from the assets of the latest GitHub release.

    generate_rootfs_json.py [--lint] [repo_dir]

--lint only validates the Dockerfile labels (no network, no write).
"""
import glob
import json
import os
import shlex
import sys
import urllib.error
import urllib.request

LABEL_PREFIX = "droidspaces."
REQUIRED = ("name", "distro", "description")
DEFAULTS = {"author": "Droidspaces developers"}
API_URL = "https://api.github.com/repos/{repo}/releases/latest"


def parse_labels(path):
    """Return {key: value} for every droidspaces.* LABEL in a Dockerfile."""
    text = open(path).read().replace("\\\n", " ")
    labels = {}
    for line in text.splitlines():
        line = line.strip()
        if not line.upper().startswith("LABEL "):
            continue
        for tok in shlex.split(line[6:]):
            key, _, value = tok.partition("=")
            if key.startswith(LABEL_PREFIX):
                labels[key[len(LABEL_PREFIX):]] = value
    return labels


def collect_templates(root):
    """Return {(arch, name): labels}. Exits non-zero on missing required labels."""
    templates, errors = {}, []
    for path in sorted(glob.glob(os.path.join(root, "templates", "*", "*.Dockerfile"))):
        arch = os.path.basename(os.path.dirname(path))
        name = os.path.basename(path)[: -len(".Dockerfile")]
        labels = {**DEFAULTS, **parse_labels(path)}
        missing = [k for k in REQUIRED if not labels.get(k)]
        if missing:
            errors.append(f"{path}: missing LABEL {', '.join(LABEL_PREFIX + k for k in missing)}")
        templates[(arch, name)] = labels
    for e in errors:
        print(e, file=sys.stderr)
    if errors:
        sys.exit(1)
    if not templates:
        print("No templates found under templates/<arch>/", file=sys.stderr)
        sys.exit(1)
    return templates


def fetch_latest_release(repo):
    req = urllib.request.Request(API_URL.format(repo=repo))
    req.add_header("Accept", "application/vnd.github+json")
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(f"Error fetching latest release for {repo}: {e.code} {e.reason}", file=sys.stderr)
        sys.exit(1)


def parse_asset_filename(name):
    """<Name>-Droidspaces-rootfs-<arch>-<date>-<version>.tar.xz -> (name, arch, date, version)"""
    if "-Droidspaces-rootfs-" not in name or not name.endswith(".tar.xz"):
        return None
    prefix, rest = name.split("-Droidspaces-rootfs-", 1)
    parts = rest[: -len(".tar.xz")].split("-")
    if len(parts) < 3:
        return None
    return prefix, parts[0], parts[1], "-".join(parts[2:])


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    root = args[0] if args else "."
    templates = collect_templates(root)
    print(f"Found {len(templates)} templates")

    if "--lint" in sys.argv:
        return

    repo = os.environ.get("GITHUB_REPOSITORY", "Droidspaces/Droidspaces-rootfs-builder")
    release = fetch_latest_release(repo)
    print(f"Release: {release.get('tag_name')} ({len(release.get('assets', []))} assets)")

    assets = {}
    for asset in release.get("assets", []):
        parsed = parse_asset_filename(asset["name"])
        if parsed:
            name, arch, date_str, version = parsed
            assets[(arch, name)] = (asset, date_str, version)

    entries, missing = [], []
    for (arch, name), labels in templates.items():
        if (arch, name) not in assets:
            missing.append(f"{arch}/{name}")
            continue
        asset, date_str, version = assets[(arch, name)]
        digest = asset.get("digest", "")
        entries.append({
            **labels,
            "architecture": arch,
            "file": name,
            "download_url": asset["browser_download_url"],
            "sha256": digest.removeprefix("sha256:"),
            "size_bytes": asset["size"],
            "version": version,
            "build_date": date_str,
        })

    if missing:
        print("Templates with no asset in the latest release:", file=sys.stderr)
        for m in missing:
            print(f"  {m}", file=sys.stderr)
        sys.exit(1)

    entries.sort(key=lambda e: (e["distro"], e["architecture"], e["name"]))
    out = os.path.join(root, "rootfs.json")
    with open(out, "w") as f:
        json.dump(entries, f, indent=2)
        f.write("\n")
    print(f"Wrote {len(entries)} entries to {out}")


if __name__ == "__main__":
    main()
