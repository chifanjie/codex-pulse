#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$project_dir/build"
app_dir="$build_dir/Codex Pulse.app"
executable_dir="$app_dir/Contents/MacOS"
resources_dir="$app_dir/Contents/Resources"
plugin_dir="$app_dir/Contents/PlugIns"
appex_dir="$plugin_dir/CodexPulseWidget.appex"
appex_executable_dir="$appex_dir/Contents/MacOS"
module_cache_dir="$build_dir/ModuleCache"

export CLANG_MODULE_CACHE_PATH="$module_cache_dir"
export SWIFT_MODULECACHE_PATH="$module_cache_dir"

case "$app_dir" in
  "$build_dir"/*) /bin/rm -rf "$app_dir" ;;
  *) printf 'Refusing to clean unexpected app path: %s\n' "$app_dir" >&2; exit 1 ;;
esac
mkdir -p \
  "$executable_dir" \
  "$resources_dir" \
  "$appex_executable_dir" \
  "$module_cache_dir"

/usr/bin/ditto "$project_dir/Resources/AppIcon.icns" \
  "$resources_dir/AppIcon.icns"

/usr/bin/swiftc \
  -O \
  -whole-module-optimization \
  -swift-version 5 \
  -parse-as-library \
  -target arm64-apple-macosx14.0 \
  -module-name CodexPulse \
  "$project_dir"/Shared/*.swift \
  "$project_dir"/Sources/*.swift \
  -framework AppKit \
  -framework ServiceManagement \
  -framework WidgetKit \
  -lsqlite3 \
  -o "$executable_dir/CodexPulse"

/usr/bin/swiftc \
  -O \
  -swift-version 5 \
  -parse-as-library \
  -application-extension \
  -target arm64-apple-macosx14.0 \
  -module-name CodexPulseWidget \
  "$project_dir"/Shared/*.swift \
  "$project_dir"/WidgetExtension/*.swift \
  -framework SwiftUI \
  -framework WidgetKit \
  -Xlinker -e \
  -Xlinker _NSExtensionMain \
  -o "$appex_executable_dir/CodexPulseWidget"

/usr/bin/ditto "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
/usr/bin/ditto "$project_dir/Resources/WidgetInfo.plist" "$appex_dir/Contents/Info.plist"
/usr/bin/plutil -lint "$app_dir/Contents/Info.plist"
/usr/bin/plutil -lint "$appex_dir/Contents/Info.plist"

/usr/bin/codesign \
  --force \
  --sign - \
  --entitlements "$project_dir/Resources/Widget.entitlements" \
  "$appex_dir"
/usr/bin/codesign --force --sign - "$app_dir"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_dir"

printf '%s\n' "$app_dir"
