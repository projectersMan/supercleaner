#!/bin/zsh
set -euo pipefail

PROJECT_ROOT=${0:A:h:h:h}
cd ${PROJECT_ROOT}
FIXTURE=${PROJECT_ROOT}/Tests/quit-without-emptying
PRODUCTS=$(swift build --show-bin-path)
APP=${FIXTURE}/QuitWithoutEmptyingHarness.app
mkdir -p ${APP}/Contents/MacOS ${APP}/Contents/Resources ${FIXTURE}/generated

# Extract the exact production delegate and reuse the existing Cancel-only test
# model/probe. This avoids a second hand-written implementation of quit logic.
/usr/bin/python3 - <<'PY'
from pathlib import Path
import hashlib
import json

root = Path.cwd()
qa = root / 'Tests/quit-without-emptying'
production = (root / 'Sources/CleanerApp/CleanerApp.swift').read_text()
marker = '@MainActor final class CleanerApplicationDelegate: NSObject, NSApplicationDelegate {'
assert production.count(marker) == 1
delegate = production[production.index(marker):]
assert delegate.rstrip().endswith('}')
(qa / 'generated/ProductionDelegate.swift').write_text('import AppKit\nimport Foundation\n\n' + delegate)
existing = (root / 'Tests/exact-trash-dialog/main.swift').read_text()
model = existing[:existing.index('@MainActor final class ExactTrashDialogHarness:')]
(qa / 'generated/ExistingCancelFixture.swift').write_text(model)
(qa / 'native-source-hashes.json').write_text(json.dumps({
    'production_delegate_sha256': hashlib.sha256(delegate.encode()).hexdigest(),
    'existing_cancel_fixture_sha256': hashlib.sha256(model.encode()).hexdigest()
}, indent=2) + '\n')
PY

swiftc -swift-version 6 -I ${PRODUCTS} -I Sources/CleanerZIP \
  Sources/CleanerApp/TrashReminderController.swift Sources/CleanerApp/TrashReminderWindowObserver.swift \
  ${FIXTURE}/generated/ProductionDelegate.swift ${FIXTURE}/generated/ExistingCancelFixture.swift \
  ${FIXTURE}/main.swift ${PRODUCTS}/CleanerCore.o -larchive -o ${APP}/Contents/MacOS/QuitWithoutEmptyingHarness
cat > ${APP}/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.example.SuperCleaner.QuitWithoutEmptyingHarness</string>
<key>CFBundleExecutable</key><string>QuitWithoutEmptyingHarness</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
ditto ${PRODUCTS}/SuperCleaner_CleanerCore.bundle ${APP}/Contents/Resources/SuperCleaner_CleanerCore.bundle
${APP}/Contents/MacOS/QuitWithoutEmptyingHarness
${APP}/Contents/MacOS/QuitWithoutEmptyingHarness --no-cleanup
