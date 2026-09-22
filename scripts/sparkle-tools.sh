#!/bin/bash
# Fetches Sparkle's command-line tools (generate_keys, generate_appcast, sign_update) once into
# build/sparkle-tools and prints the bin directory. Version and checksum are pinned to the same
# Sparkle release the app links against (project.yml).
set -euo pipefail
cd "$(dirname "$0")/.."
version="2.10.0"
sha="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
dir="build/sparkle-tools"
if [ ! -x "$dir/bin/generate_appcast" ]; then
  mkdir -p "$dir"
  tarball="$dir/Sparkle-$version.tar.xz"
  [ -f "$tarball" ] || curl -sSL -o "$tarball" "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz"
  echo "$sha  $tarball" | shasum -a 256 -c - >/dev/null || { rm -f "$tarball"; echo "Sparkle tarball checksum mismatch; deleted it, run again"; exit 1; }
  tar -xJf "$tarball" -C "$dir"
fi
echo "$PWD/$dir/bin"
