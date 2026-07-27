#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
test_dir="$project_dir/build/tests"
mkdir -p "$test_dir"

/usr/bin/swiftc \
  -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -module-name CodexPulseTests \
  "$project_dir/Shared/WidgetSnapshot.swift" \
  "$project_dir/Sources/Models.swift" \
  "$project_dir/Sources/LocalDataProvider.swift" \
  "$project_dir/Tests/LocalDataProviderTests.swift" \
  -lsqlite3 \
  -o "$test_dir/LocalDataProviderTests"

"$test_dir/LocalDataProviderTests"
