#!/bin/zsh
set -euo pipefail
# Read-only gate. Does not register Helper, prompt for administrator rights or
# read private keys. Called again on the stapled staged copy before publication.
SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
APP=${1:-${PROJECT_ROOT}/build/SuperCleaner.app}
[[ ${APP} == /* && -d ${APP} && ! -L ${APP} ]] || { print -u2 "FAIL: explicit regular app bundle required"; exit 1; }
CONFIG=${APP}/Contents/Resources/release-configuration.json
CHECKER=${PROJECT_ROOT}/.build/release-scratch/arm64-apple-macosx/release/CoreContractChecks
if [[ ! -x ${CHECKER} ]]; then
  CHECKER=${PROJECT_ROOT}/.build/release-scratch/x86_64-apple-macosx/release/CoreContractChecks
fi
[[ -x ${CHECKER} && -f ${CONFIG} ]] || { print -u2 "FAIL: built checker and complete public release configuration required"; exit 1; }
${CHECKER} --validate-release-config ${CONFIG} --complete
TEAM=$(/usr/bin/plutil -extract teamIdentifier raw -o - ${CONFIG})
BUNDLE_ID=$(/usr/bin/plutil -extract bundleIdentifier raw -o - ${CONFIG})
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' ${APP}/Contents/Info.plist) == ${BUNDLE_ID} ]] || { print -u2 "FAIL: mismatched app identity"; exit 1; }
REQUIREMENT="anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"${TEAM}\" and ! entitlement[\"com.apple.security.get-task-allow\"] exists"
SPARKLE=${APP}/Contents/Frameworks/Sparkle.framework/Versions/B
TARGETS=(${APP} ${APP}/Contents/MacOS/supercleaner ${APP}/Contents/Library/LaunchServices/${BUNDLE_ID}.helper
  ${APP}/Contents/Frameworks/Sparkle.framework ${SPARKLE}/Autoupdate ${SPARKLE}/Updater.app
  ${SPARKLE}/XPCServices/Downloader.xpc ${SPARKLE}/XPCServices/Installer.xpc)
for TARGET in ${TARGETS[@]}; do
  /usr/bin/codesign --verify --strict --all-architectures -R="${REQUIREMENT}" ${TARGET}
  DETAILS=$(/usr/bin/codesign -dv --verbose=4 ${TARGET} 2>&1)
  [[ ${DETAILS} == *"runtime)"* && ${DETAILS} == *"Timestamp="* && ${DETAILS} != *"Signature=adhoc"* ]] || { print -u2 "FAIL: Hardened Runtime and secure timestamp required: ${TARGET}"; exit 1; }
done
for PAIR in "${APP}|${BUNDLE_ID}" "${APP}/Contents/MacOS/supercleaner|${BUNDLE_ID}.cli" "${APP}/Contents/Library/LaunchServices/${BUNDLE_ID}.helper|${BUNDLE_ID}.helper"; do
  /usr/bin/codesign --verify --strict -R="${REQUIREMENT} and identifier \"${PAIR#*|}\"" "${PAIR%%|*}"
done
/usr/bin/codesign --verify --deep --strict --all-architectures ${APP}
# No library-validation / unsigned-executable escape hatch in the main app.
ENTITLEMENTS=$(/usr/bin/codesign -d --entitlements :- ${APP} 2>/dev/null)
[[ ${ENTITLEMENTS} != *"com.apple.security.cs.disable-library-validation"* && ${ENTITLEMENTS} != *"com.apple.security.cs.allow-unsigned-executable-memory"* && ${ENTITLEMENTS} != *"com.apple.security.cs.disable-executable-page-protection"* ]] || { print -u2 "FAIL: unsafe production entitlements"; exit 1; }
${APP}/Contents/MacOS/CleanerApp --update-self-check --require-production-updater
print "PASS: Developer ID, exact identities, same team, Hardened Runtime, timestamps and nested signatures"
