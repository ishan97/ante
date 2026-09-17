#!/bin/bash
# Generates Ante.xcodeproj from project.yml. Run after cloning or after editing project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 || { echo "xcodegen is missing and Homebrew is not installed; see https://github.com/yonaskolb/XcodeGen"; exit 1; }
  echo "installing xcodegen with Homebrew (Ctrl-C within 3 s to abort)"
  sleep 3
  brew install xcodegen
fi
xcodegen generate --spec project.yml
echo "generated Ante.xcodeproj"
