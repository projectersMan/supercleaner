#!/bin/zsh
set -euo pipefail

client_repository="$(cd "$(dirname "$0")/../.." && pwd)"
client_products="$1"
client_module_cache="$2"
client_runtime="$client_repository/Tests/commercial-launch/fixtures/client-runtime"
cd "$client_repository"
mkdir -p Tests/commercial-launch/fixtures
trap 'rm -f "$client_runtime"' EXIT
swiftc -disable-sandbox -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos13.0" \
    -module-cache-path "$client_module_cache" \
    -I "$client_products" -I Sources/CleanerZIP \
    Sources/CleanerApp/CommercialAccess.swift Sources/CleanerApp/CommercialSettingsView.swift \
    Tests/commercial-launch/client-runtime.swift "$client_products/CleanerCore.o" -o "$client_runtime"
PACKAGE_RESOURCE_BUNDLE_PATH="$client_products" "$client_runtime"
python3 Scripts/check-localizations.py
