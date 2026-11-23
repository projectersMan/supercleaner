#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h:h:h}
SOURCES=${0:A:h}
OUTPUT=${ROOT}/Tests/temporary/native-checks
cd ${ROOT}
/bin/mkdir -p ${OUTPUT}
CHECKS=("$@")
if (( $# == 0 )); then CHECKS=(trash quit termination); fi
PRODUCTS=

prepare_core() {
  if [[ -n ${PRODUCTS} ]]; then return; fi
  local options=(--disable-sandbox --cache-path ${ROOT}/.build/release-cache --scratch-path ${ROOT}/.build/release-scratch --configuration release)
  swift build ${options[@]} --product CleanerApp
  PRODUCTS=$(swift build ${options[@]} --show-bin-path)
}

build_trash_harness() {
  local name=$1
  shift
  prepare_core
  local app=${OUTPUT}/${name}.app
  /bin/mkdir -p ${app}/Contents/MacOS ${app}/Contents/Resources
  swiftc -swift-version 6 -I ${PRODUCTS}/Modules -I Sources/CleanerZIP \
    Sources/CleanerApp/TrashReminderController.swift Sources/CleanerApp/TrashReminderWindowObserver.swift \
    "$@" ${PRODUCTS}/CleanerCore.build/*.o -larchive -o ${app}/Contents/MacOS/${name}
  /usr/bin/python3 - ${app} ${name} <<'PY'
from pathlib import Path
import plistlib
import sys
app = Path(sys.argv[1])
name = sys.argv[2]
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': f'org.example.SuperCleaner.{name}',
    'CFBundleExecutable': name, 'CFBundleName': name,
    'CFBundlePackageType': 'APPL', 'LSUIElement': True,
}))
PY
  /usr/bin/ditto ${PRODUCTS}/SuperCleaner_CleanerCore.bundle ${app}/Contents/Resources/SuperCleaner_CleanerCore.bundle
}

for check in ${CHECKS[@]}; do
  case ${check} in
    trash)
      build_trash_harness TrashDialog ${SOURCES}/TrashDialog/main.swift
      ${OUTPUT}/TrashDialog.app/Contents/MacOS/TrashDialog
      ;;
    quit)
      /bin/mkdir -p ${OUTPUT}/quit
      /usr/bin/python3 - ${ROOT} ${SOURCES} ${OUTPUT}/quit <<'PY'
from pathlib import Path
import sys
root, sources, output = map(Path, sys.argv[1:])
production = (root / 'Sources/CleanerApp/CleanerApp.swift').read_text()
marker = '@MainActor final class CleanerApplicationDelegate: NSObject, NSApplicationDelegate {'
assert production.count(marker) == 1
(output / 'ProductionDelegate.swift').write_text('import AppKit\nimport Foundation\n\n' + production[production.index(marker):])
existing = (sources / 'TrashDialog/main.swift').read_text()
(output / 'CancelFixture.swift').write_text(existing[:existing.index('@MainActor final class ExactTrashDialogHarness:')])
PY
      build_trash_harness Quit ${OUTPUT}/quit/ProductionDelegate.swift ${OUTPUT}/quit/CancelFixture.swift ${SOURCES}/Quit/main.swift
      ${OUTPUT}/Quit.app/Contents/MacOS/Quit
      ${OUTPUT}/Quit.app/Contents/MacOS/Quit --no-cleanup
      ;;
    termination)
      /usr/bin/python3 ${SOURCES}/check-appkit-termination.py
      ;;
    icons)
      /bin/mkdir -p ${OUTPUT}/icons
      swiftc -parse-as-library Sources/CleanerApp/ApplicationIconView.swift ${SOURCES}/Icons/main.swift -o ${OUTPUT}/icons/check
      ${OUTPUT}/icons/check
      ;;
    agent)
      prepare_core
      /bin/mkdir -p ${OUTPUT}/agent
      swiftc -parse-as-library -I ${PRODUCTS}/Modules -I Sources/CleanerZIP \
        ${SOURCES}/AgentOverlap/analysis-contract.swift ${PRODUCTS}/CleanerCore.build/*.o \
        ${PRODUCTS}/AgentOverlapAI.build/*.o -larchive -o ${OUTPUT}/agent/analysis
      PACKAGE_RESOURCE_BUNDLE_PATH=${PRODUCTS} ${OUTPUT}/agent/analysis
      swiftc -parse-as-library -I ${PRODUCTS}/Modules -I Sources/CleanerZIP \
        ${SOURCES}/AgentOverlap/label-contract.swift Sources/CleanerApp/AgentContainmentLabel.swift \
        ${PRODUCTS}/CleanerCore.build/*.o -larchive -o ${OUTPUT}/agent/label
      PACKAGE_RESOURCE_BUNDLE_PATH=${PRODUCTS} ${OUTPUT}/agent/label ${OUTPUT}/agent/status.png
      PACKAGE_RESOURCE_BUNDLE_PATH=${PRODUCTS} ${OUTPUT}/agent/label ${OUTPUT}/agent/top-three.png ${OUTPUT}/agent/index.plist
      ;;
    signing)
      /bin/zsh ${SOURCES}/check-signing.sh
      ;;
    *)
      print -u2 'Usage: run-checks.sh [trash|quit|termination|icons|agent|signing ...]'
      exit 2
      ;;
  esac
done
