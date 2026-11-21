#!/bin/zsh
set -euo pipefail
# --preflight is read-only; --publish creates staging; --resume continues the
# same immutable Apple submissions. Nothing uploads to the public feed host.
SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
MODE=${1:---preflight}
[[ ${MODE} == --preflight || ${MODE} == --publish || ${MODE} == --resume ]] || { print -u2 "Usage: publish-release.sh [--preflight|--publish|--resume]"; exit 1; }
[[ -n ${SUPERCLEANER_RELEASE_CONFIG:-} && ${SUPERCLEANER_RELEASE_CONFIG} == /* && -n ${SUPERCLEANER_COMMERCIAL_CONFIG:-} && ${SUPERCLEANER_COMMERCIAL_CONFIG} == /* && -n ${SUPERCLEANER_SIGN_IDENTITY:-} && ${SUPERCLEANER_SIGN_IDENTITY} != - && -n ${SUPERCLEANER_NOTARY_PROFILE:-} && -n ${SUPERCLEANER_SPARKLE_ACCOUNT:-} ]] || { print -u2 "FAIL: public release and commercial configurations, Developer ID, notary Keychain Profile and Sparkle Keychain account are required"; exit 1; }
VERSION_VALUES=("${(@f)$(/usr/bin/python3 "${SCRIPT_DIR}/version.py" resolve)}")
DISPLAY_VERSION=${VERSION_VALUES[1]}
BUILD_NUMBER=${VERSION_VALUES[2]}
PREVIOUS_BUILD=${SUPERCLEANER_PREVIOUS_BUILD_NUMBER:-}
[[ ${PREVIOUS_BUILD} =~ '^(0|[1-9][0-9]{0,17})$' ]] || { print -u2 "FAIL: previous published build (0 for first release) required"; exit 1; }
(( BUILD_NUMBER > PREVIOUS_BUILD )) || { print -u2 "FAIL: release build must increase; downgrade/replay publication refused"; exit 1; }
APP=${PROJECT_ROOT}/build/SuperCleaner.app
${SCRIPT_DIR}/check-production-signing.sh ${APP}
CONFIG=${APP}/Contents/Resources/release-configuration.json
/usr/bin/cmp -s ${SUPERCLEANER_RELEASE_CONFIG} ${CONFIG} || { print -u2 "FAIL: rebuild with the requested public configuration first"; exit 1; }
/usr/bin/cmp -s ${SUPERCLEANER_COMMERCIAL_CONFIG} ${APP}/Contents/Resources/commercial-configuration.json || { print -u2 "FAIL: rebuild with the requested commercial configuration first"; exit 1; }
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' ${APP}/Contents/Info.plist) == ${BUILD_NUMBER} && $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' ${APP}/Contents/Info.plist) == ${DISPLAY_VERSION} ]] || { print -u2 "FAIL: requested version differs from built app"; exit 1; }
FEED=$(/usr/bin/plutil -extract applicationUpdateURL raw -o - ${CONFIG})
FEED_NAME=${FEED:t}
[[ ${FEED_NAME} =~ '^[A-Za-z0-9._-]+\.xml$' ]] || { print -u2 "FAIL: application update URL must name an appcast XML"; exit 1; }
SPARKLE_BIN=${PROJECT_ROOT}/.build/release-scratch/artifacts/sparkle/Sparkle/bin
[[ -x ${SPARKLE_BIN}/generate_appcast ]] || { print -u2 "FAIL: pinned Sparkle distribution missing"; exit 1; }
[[ -x ${SCRIPT_DIR}/create-dmg.sh ]] || { print -u2 "FAIL: DMG creation tool missing or not executable"; exit 1; }
if [[ ${MODE} == --preflight ]]; then
  print "PASS: local release preflight; notary credentials and private signing-key access are NOT validated"
  exit 0
fi
OUTPUT=${PROJECT_ROOT}/build/releases/${DISPLAY_VERSION}-${BUILD_NUMBER}
[[ ! -L ${PROJECT_ROOT}/build && ! -L ${PROJECT_ROOT}/build/releases ]] || { print -u2 "FAIL: linked staging parent refused"; exit 1; }
[[ ! -L ${OUTPUT} ]] || { print -u2 "FAIL: linked staging refused"; exit 1; }
SOURCE_CDHASH=$(/usr/bin/codesign -dv --verbose=4 ${APP} 2>&1 | /usr/bin/awk -F= '/^CDHash=/ {print $2}')
[[ ${SOURCE_CDHASH} =~ '^[0-9a-fA-F]{40,64}$' ]] || { print -u2 "FAIL: source signature hash unavailable"; exit 1; }
if [[ ${MODE} == --publish ]]; then
  [[ ! -e ${OUTPUT} ]] || { print -u2 "FAIL: release staging exists; use --resume to continue its submissions"; exit 1; }
  /bin/mkdir -p ${OUTPUT}/public
  print -r -- ${SOURCE_CDHASH} > ${OUTPUT}/source-cdhash.txt
elif [[ ! -f ${OUTPUT}/source-cdhash.txt || $(<${OUTPUT}/source-cdhash.txt) != ${SOURCE_CDHASH} ]]; then
  print -u2 "FAIL: resume requires the identical signed source app and original staging"; exit 1
fi
if [[ ! -e ${OUTPUT}/SuperCleaner.app ]]; then
  PENDING_APP=${OUTPUT}/SuperCleaner.pending.app
  [[ ! -L ${PENDING_APP} ]] || { print -u2 "FAIL: linked pending app refused"; exit 1; }
  /usr/bin/ditto ${APP} ${PENDING_APP}
  ${SCRIPT_DIR}/check-production-signing.sh ${PENDING_APP}
  /bin/mv ${PENDING_APP} ${OUTPUT}/SuperCleaner.app
fi
${SCRIPT_DIR}/check-production-signing.sh ${OUTPUT}/SuperCleaner.app
STAGED_CDHASH=$(/usr/bin/codesign -dv --verbose=4 ${OUTPUT}/SuperCleaner.app 2>&1 | /usr/bin/awk -F= '/^CDHash=/ {print $2}')
[[ ${STAGED_CDHASH} == ${SOURCE_CDHASH} ]] || { print -u2 "FAIL: staged app differs from the original signed build"; exit 1; }
# First notarize and staple the installed app itself; then notarize the DMG
# containing that stapled app. Retain immutable submission archives for resume.
APP_ARCHIVE=${OUTPUT}/submitted-app.zip
if [[ ! -e ${APP_ARCHIVE} ]]; then
  [[ ! -L ${APP_ARCHIVE}.pending ]] || { print -u2 "FAIL: linked pending archive refused"; exit 1; }
  /usr/bin/ditto -c -k --keepParent ${OUTPUT}/SuperCleaner.app ${APP_ARCHIVE}.pending
  /bin/mv ${APP_ARCHIVE}.pending ${APP_ARCHIVE}
fi
/bin/zsh ${SCRIPT_DIR}/notarize-artifact.sh ${APP_ARCHIVE} ${OUTPUT}/notary-app
/usr/bin/xcrun stapler staple ${OUTPUT}/SuperCleaner.app
/usr/bin/xcrun stapler validate ${OUTPUT}/SuperCleaner.app
/usr/sbin/spctl --assess --type execute --verbose=2 ${OUTPUT}/SuperCleaner.app
ARCHIVE=${OUTPUT}/public/SuperCleaner-${BUILD_NUMBER}.dmg
SUBMITTED_DMG=${OUTPUT}/submitted.dmg
if [[ ! -e ${SUBMITTED_DMG} ]]; then
  PENDING_DMG=${OUTPUT}/submitted.pending.dmg
  [[ ! -L ${PENDING_DMG} ]] || { print -u2 "FAIL: linked pending disk image refused"; exit 1; }
  # This generated file has never been submitted. Recreate interrupted output;
  # the immutable submission and Apple's retained ID are never overwritten.
  if [[ -f ${PENDING_DMG} ]]; then /bin/rm -f -- ${PENDING_DMG}; fi
  ${SCRIPT_DIR}/create-dmg.sh ${OUTPUT}/SuperCleaner.app ${PENDING_DMG}
  /bin/zsh ${SCRIPT_DIR}/sign-release-artifact.sh ${PENDING_DMG} ${SUBMITTED_DMG}
fi
/usr/bin/codesign --verify --strict --verbose=2 ${SUBMITTED_DMG}
/bin/zsh ${SCRIPT_DIR}/notarize-artifact.sh ${SUBMITTED_DMG} ${OUTPUT}/notary-dmg
/bin/cp ${SUBMITTED_DMG} ${ARCHIVE}
/usr/bin/xcrun stapler staple ${ARCHIVE}
/usr/bin/xcrun stapler validate ${ARCHIVE}
/usr/bin/codesign --verify --strict --verbose=2 ${ARCHIVE}
/usr/bin/hdiutil verify ${ARCHIVE}
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 ${ARCHIVE}
${SCRIPT_DIR}/check-production-signing.sh ${OUTPUT}/SuperCleaner.app
${SPARKLE_BIN}/generate_appcast --account "${SUPERCLEANER_SPARKLE_ACCOUNT}" --maximum-deltas 0 --download-url-prefix "${FEED:h}/" -o ${OUTPUT}/public/${FEED_NAME} ${OUTPUT}/public
RELEASE_BIN=$(/usr/bin/swift build --package-path ${PROJECT_ROOT} --scratch-path ${PROJECT_ROOT}/.build/release-scratch --configuration release --show-bin-path)
CHECKER=${RELEASE_BIN}/CoreContractChecks
${CHECKER} --validate-application-release ${CONFIG} ${OUTPUT}/public/${FEED_NAME} ${ARCHIVE} ${BUILD_NUMBER} 13.0
# Marker exists only after every check. Publish the DMG first, then the signed
# XML atomically; never publish notary logs, source app or private keys.
/usr/bin/touch ${OUTPUT}/LOCAL-GATES-PASSED
print "PASS: signed, notarized and stapled DMG plus signed appcast verified. Upload only ${OUTPUT}/public after clean-Mac acceptance. No upload performed."
