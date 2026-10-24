#!/usr/bin/env bash
# Install the four editing tools on Ubuntu x86_64 (such as GitHub Actions).
# Usage: bash scripts/install-video-tools.sh
# Python package remains in .venv-video-tools/; activate before using faster-whisper.
set -euo pipefail

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  echo "This installer supports Linux x86_64 only." >&2
  exit 1
fi
if (( $(node -p 'Number(process.versions.node.split(".")[0])') < 22 )); then
  echo "Node.js 22+ is required for HyperFrames." >&2
  exit 1
fi

# 1. Video cut/export plus system utilities
sudo apt-get update -qq
sudo apt-get install -y -qq ffmpeg ca-certificates

# 2. Transcription Python dependency, in an isolated environment
python3 -m venv .venv-video-tools
. .venv-video-tools/bin/activate
python -m pip install --upgrade pip
python -m pip install faster-whisper

# 3. HyperFrames composition/caption CLI
npm install --global hyperframes

# 4. Auto-Editor: new CLI releases are official binaries, not pip packages.
# Choose the Linux x86_64 release asset from the official GitHub API.
mkdir -p "$HOME/.local/bin"
python - <<'PY'
import io
import json
import os
from pathlib import Path
import re
import shutil
import stat
import tarfile
import tempfile
import urllib.request
import zipfile

headers = {"User-Agent": "video-tools-installer", "Accept": "application/vnd.github+json"}
api = "https://api.github.com/repos/WyattBlue/auto-editor/releases/latest"
with urllib.request.urlopen(urllib.request.Request(api, headers=headers), timeout=30) as r:
    release = json.load(r)
assets = release.get("assets", [])
print("Auto-Editor release:", release.get("tag_name"), flush=True)
print("Available assets:", [a.get("name") for a in assets], flush=True)
candidates = []
for a in assets:
    name = a.get("name", "")
    low = name.lower()
    if ("linux" in low and re.search(r"(x86[_-]?64|amd64|x64)", low)
            and not re.search(r"(arm|aarch|sha|checksum|signature|\\.sig|source)", low)):
        candidates.append(a)
if len(candidates) != 1:
    raise SystemExit(f"Expected one Linux x86_64 Auto-Editor asset, got {len(candidates)}")
asset = candidates[0]
url = asset["browser_download_url"]
if not url.startswith("https://github.com/WyattBlue/auto-editor/releases/download/"):
    raise SystemExit("Refusing unexpected Auto-Editor download URL")
with tempfile.TemporaryDirectory() as tmp:
    temp = Path(tmp)
    blob = temp / asset["name"]
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "video-tools-installer"}), timeout=180) as r:
        with blob.open("wb") as f:
            shutil.copyfileobj(r, f)
    unpacked = temp / "unpacked"
    unpacked.mkdir()
    if tarfile.is_tarfile(blob):
        with tarfile.open(blob) as tar:
            tar.extractall(unpacked, filter="data")
    elif zipfile.is_zipfile(blob):
        with zipfile.ZipFile(blob) as z:
            z.extractall(unpacked)
    else:
        shutil.copy2(blob, unpacked / "auto-editor")
    found = [p for p in unpacked.rglob("*") if p.is_file() and p.name == "auto-editor"]
    if len(found) != 1:
        raise SystemExit(f"Could not identify executable in Auto-Editor asset: {asset['name']}")
    dest = Path.home() / ".local" / "bin" / "auto-editor"
    shutil.copyfile(found[0], dest)
    dest.chmod(dest.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print("Installed", dest, flush=True)
PY

export PATH="$HOME/.local/bin:$PATH"
echo "Checking installed tools..."
ffmpeg -version | head -n 1
python -c 'from faster_whisper import WhisperModel; print("faster-whisper: import OK")'
auto-editor --version
hyperframes --version
echo "All four tools installed and basic checks passed."
