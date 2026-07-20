#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="${QIEMAN_CLI_OUTPUT:-$ROOT_DIR/dist/bin/qieman-cli}"
TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-14.0}"

mkdir -p "$(dirname "$OUTPUT_PATH")"

swiftc \
  "$ROOT_DIR/macos-app/Support/ValueFormatting.swift" \
  "$ROOT_DIR/macos-app/Core/Models.swift" \
  "$ROOT_DIR/macos-app/Core/NativeSnapshotStore.swift" \
  "$ROOT_DIR/macos-app/Core/MenuBarTicker/MenuBarTickerTypes.swift" \
  "$ROOT_DIR/macos-app/Core/QiemanNativeClient.swift" \
  "$ROOT_DIR/macos-app/Core/QiemanPlatformNativeClient.swift" \
  "$ROOT_DIR/macos-app/Core/QiemanCommandLine.swift" \
  "$ROOT_DIR/macos-app/CLI/main.swift" \
  -parse-as-library \
  -O \
  -whole-module-optimization \
  -target "${TARGET_ARCH}-apple-macos${MIN_MACOS_VERSION}" \
  -o "$OUTPUT_PATH"

echo "$OUTPUT_PATH"
