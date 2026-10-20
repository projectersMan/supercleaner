#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
APP=${PROJECT_ROOT}/build/SuperCleaner.app

[[ -d ${APP} ]] || { print -u2 "FAIL: app bundle missing: ${APP}"; exit 1; }
[[ -f ${APP}/Contents/Info.plist ]] || { print -u2 "FAIL: Info.plist missing"; exit 1; }
ICON_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' ${APP}/Contents/Info.plist)
[[ ${ICON_NAME} == AppIcon.icns ]] || { print -u2 "FAIL: app icon declaration mismatch"; exit 1; }
[[ -f ${APP}/Contents/Resources/${ICON_NAME} ]] || { print -u2 "FAIL: app icon missing"; exit 1; }
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' ${APP}/Contents/Info.plist)
DISPLAY_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' ${APP}/Contents/Info.plist)
[[ ${DISPLAY_NAME} == SuperCleaner ]] || { print -u2 "FAIL: app display name mismatch"; exit 1; }
HELPER_ID=${BUNDLE_ID}.helper
[[ -x ${APP}/Contents/MacOS/CleanerApp ]] || { print -u2 "FAIL: CleanerApp missing"; exit 1; }
[[ -x ${APP}/Contents/Library/LaunchServices/${HELPER_ID} ]] || { print -u2 "FAIL: helper missing"; exit 1; }
DAEMON_PLIST=${APP}/Contents/Library/LaunchDaemons/${HELPER_ID}.plist
[[ -f ${DAEMON_PLIST} ]] || { print -u2 "FAIL: SMAppService daemon plist missing"; exit 1; }
[[ $(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' ${DAEMON_PLIST}) == Contents/Library/LaunchServices/${HELPER_ID} ]] || { print -u2 "FAIL: BundleProgram mismatch"; exit 1; }
[[ $(/usr/libexec/PlistBuddy -c 'Print :Label' ${DAEMON_PLIST}) == ${HELPER_ID} ]] || { print -u2 "FAIL: Helper label mismatch"; exit 1; }
[[ $(/usr/libexec/PlistBuddy -c "Print :MachServices:${HELPER_ID}" ${DAEMON_PLIST}) == true ]] || { print -u2 "FAIL: Helper Mach service mismatch"; exit 1; }
[[ -f ${APP}/Contents/Resources/Rules/base-rules.json ]] || { print -u2 "FAIL: bundled rules missing"; exit 1; }
[[ -f ${APP}/Contents/Resources/SuperCleaner_CleanerCore.bundle/base-rules.json ]] || { print -u2 "FAIL: SwiftPM CleanerCore resource bundle missing"; exit 1; }
[[ -f ${APP}/Contents/Resources/Sparkle-LICENSE.txt && -f ${APP}/Contents/Frameworks/Sparkle.framework/Sparkle ]] || { print -u2 "FAIL: embedded updater missing"; exit 1; }

MINIMUM=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' ${APP}/Contents/Info.plist)
[[ ${MINIMUM} == 13.0 ]] || { print -u2 "FAIL: minimum macOS is ${MINIMUM}"; exit 1; }
/usr/bin/codesign --verify --deep --strict --verbose=2 ${APP}
if [[ ${SUPERCLEANER_REQUIRE_STABLE_SIGNING:-0} == 1 ]]; then
  SIGNATURE=$(/usr/bin/codesign -dv ${APP} 2>&1)
  if [[ ${SIGNATURE} == *"Signature=adhoc"* ]]; then
    print -u2 "FAIL: a certificate-signed app is required for stable privacy authorization across builds"
    exit 1
  fi
fi
${APP}/Contents/MacOS/CleanerApp --smoke-test
${APP}/Contents/MacOS/CleanerApp --update-self-check
print "PASS: SuperCleaner.app structure, signature, and smoke flow verified"
