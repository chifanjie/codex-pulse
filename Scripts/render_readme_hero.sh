#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
build_dir="$repo_root/build/readme-hero"
module_cache="$build_dir/module-cache"

mkdir -p "$build_dir" "$module_cache"

xcrun swiftc \
  -D PROMO_RENDER \
  -target arm64-apple-macosx14.0 \
  -module-cache-path "$module_cache" \
  "$repo_root/Shared/WidgetSnapshot.swift" \
  "$repo_root/WidgetExtension/CodexPulseWidget.swift" \
  -o "$build_dir/render-readme-hero"

(
  cd "$repo_root"
  "$build_dir/render-readme-hero" "$repo_root/Assets/codex-pulse-hero.png"
)
