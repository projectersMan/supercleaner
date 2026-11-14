#!/bin/zsh
set -euo pipefail

PROJECT_ROOT=${0:A:h:h:h}
cd ${PROJECT_ROOT}
swift build --product CleanerApp
PRODUCTS=$(swift build --show-bin-path)
FIXTURE=${PROJECT_ROOT}/Tests/trash-close-reminder
APP=${FIXTURE}/TrashReminderHarness.app
mkdir -p ${APP}/Contents/MacOS ${APP}/Contents/Resources
swiftc -swift-version 6 -I ${PRODUCTS} -I Sources/CleanerZIP \
  Sources/CleanerApp/TrashReminderController.swift Sources/CleanerApp/TrashReminderWindowObserver.swift \
  ${FIXTURE}/main.swift ${PRODUCTS}/CleanerCore.o -larchive -o ${APP}/Contents/MacOS/TrashReminderHarness
cp ${FIXTURE}/Info.plist ${APP}/Contents/Info.plist
ditto ${PRODUCTS}/SuperCleaner_CleanerCore.bundle ${APP}/Contents/Resources/SuperCleaner_CleanerCore.bundle
print "Built ${APP}"
