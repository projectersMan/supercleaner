#!/bin/zsh
set -euo pipefail

PROJECT_ROOT=${0:A:h:h:h}
cd ${PROJECT_ROOT}
PRODUCTS=$(swift build --show-bin-path)
FIXTURE=${PROJECT_ROOT}/Tests/exact-trash-dialog
APP=${FIXTURE}/ExactTrashDialogHarness.app
mkdir -p ${APP}/Contents/MacOS ${APP}/Contents/Resources
swiftc -swift-version 6 -I ${PRODUCTS} -I Sources/CleanerZIP \
  Sources/CleanerApp/TrashReminderController.swift Sources/CleanerApp/TrashReminderWindowObserver.swift \
  ${FIXTURE}/main.swift ${PRODUCTS}/CleanerCore.o -larchive -o ${APP}/Contents/MacOS/ExactTrashDialogHarness
cat > ${APP}/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.example.SuperCleaner.ExactTrashDialogHarness</string>
<key>CFBundleExecutable</key><string>ExactTrashDialogHarness</string>
<key>CFBundleName</key><string>ExactTrashDialogHarness</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
ditto ${PRODUCTS}/SuperCleaner_CleanerCore.bundle ${APP}/Contents/Resources/SuperCleaner_CleanerCore.bundle
${APP}/Contents/MacOS/ExactTrashDialogHarness "$@"
