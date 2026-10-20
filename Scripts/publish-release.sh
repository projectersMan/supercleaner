#!/bin/zsh
set -euo pipefail
# --preflight is read-only. --publish explicitly submits to Apple's notary
# service and creates a NEW staging directory; it never uploads to a feed host.
SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
MODE=${1:---preflight}
[[ ${MODE} == --preflight || ${MODE} == --publish ]] || { print -u2 "Usage: publish-release.sh [--preflight|--publish]"; exit 1; }
[[ -n ${SUPERCLEANER_RELEASE_CONFIG:-} && ${SUPERCLEANER_RELEASE_CONFIG} == /* && -n ${SUPERCLEANER_SIGN_IDENTITY:-} && ${SUPERCLEANER_SIGN_IDENTITY} != - && -n ${SUPERCLEANER_NOTARY_PROFILE:-} && -n ${SUPERCLEANER_SPARKLE_ACCOUNT:-} ]] || { print -u2 "FAIL: formal public config, signing identity, notary Keychain Profile and Sparkle Keychain account are required"; exit 1; }
BUILD_NUMBER=${SUPERCLEANER_BUILD_NUMBER:-}
PREVIOUS_BUILD=${SUPERCLEANER_PREVIOUS_BUILD_NUMBER:-}
[[ ${BUILD_NUMBER} =~ '^[1-9][0-9]{0,17}$' && ${PREVIOUS_BUILD} =~ '^(0|[1-9][0-9]{0,17})$' && ${SUPERCLEANER_VERSION:-} =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 "FAIL: explicit version/build and previous published build (0 for first release) required"; exit 1; }
(( BUILD_NUMBER > PREVIOUS_BUILD )) || { print -u2 "FAIL: release build must increase; downgrade/replay publication refused"; exit 1; }
APP=${PROJECT_ROOT}/build/SuperCleaner.app
${SCRIPT_DIR}/check-production-signing.sh ${APP}
CONFIG=${APP}/Contents/Resources/release-configuration.json
/usr/bin/cmp -s ${SUPERCLEANER_RELEASE_CONFIG} ${CONFIG} || { print -u2 "FAIL: rebuild with the requested public configuration first"; exit 1; }
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' ${APP}/Contents/Info.plist) == ${BUILD_NUMBER} && $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' ${APP}/Contents/Info.plist) == ${SUPERCLEANER_VERSION} ]] || { print -u2 "FAIL: requested version differs from built app"; exit 1; }
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
OUTPUT=${PROJECT_ROOT}/build/releases/${SUPERCLEANER_VERSION}-${BUILD_NUMBER}
[[ ! -L ${PROJECT_ROOT}/build && ! -L ${PROJECT_ROOT}/build/releases ]] || { print -u2 "FAIL: linked staging parent refused"; exit 1; }
[[ ! -e ${OUTPUT} && ! -L ${OUTPUT} ]] || { print -u2 "FAIL: release staging already exists; refusing overwrite"; exit 1; }
/bin/mkdir -p ${PROJECT_ROOT}/build/releases
/bin/mkdir ${OUTPUT}
/usr/bin/ditto ${APP} ${OUTPUT}/SuperCleaner.app
/bin/mkdir ${OUTPUT}/public
ARCHIVE=${OUTPUT}/public/SuperCleaner-${BUILD_NUMBER}.dmg
${SCRIPT_DIR}/create-dmg.sh ${OUTPUT}/SuperCleaner.app ${ARCHIVE}
/usr/bin/codesign --force --sign "${SUPERCLEANER_SIGN_IDENTITY}" --timestamp ${ARCHIVE}
/usr/bin/codesign --verify --strict --verbose=2 ${ARCHIVE}
/usr/bin/xcrun notarytool submit ${ARCHIVE} --keychain-profile "${SUPERCLEANER_NOTARY_PROFILE}" --wait --timeout 30m --output-format json > ${OUTPUT}/notary-result.json
[[ $(/usr/bin/plutil -extract status raw -o - ${OUTPUT}/notary-result.json) == Accepted ]] || { print -u2 "FAIL: notarization not accepted; staging retained, nothing publishable"; exit 1; }
/usr/bin/xcrun stapler staple ${ARCHIVE}
/usr/bin/xcrun stapler validate ${ARCHIVE}
/usr/bin/codesign --verify --strict --verbose=2 ${ARCHIVE}
/usr/bin/hdiutil verify ${ARCHIVE}
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 ${ARCHIVE}
${SCRIPT_DIR}/check-production-signing.sh ${OUTPUT}/SuperCleaner.app
${SPARKLE_BIN}/generate_appcast --account "${SUPERCLEANER_SPARKLE_ACCOUNT}" --maximum-deltas 0 --download-url-prefix "${FEED:h}/" -o ${OUTPUT}/public/${FEED_NAME} ${OUTPUT}/public
CHECKER=${PROJECT_ROOT}/.build/release-scratch/arm64-apple-macosx/release/CoreContractChecks
[[ -x ${CHECKER} ]] || CHECKER=${PROJECT_ROOT}/.build/release-scratch/x86_64-apple-macosx/release/CoreContractChecks
${CHECKER} --validate-application-release ${CONFIG} ${OUTPUT}/public/${FEED_NAME} ${ARCHIVE} ${BUILD_NUMBER} 13.0
# Marker exists only after every check. Publish the DMG first, then the signed
# XML atomically; never publish notary logs, source app or private keys.
/usr/bin/touch ${OUTPUT}/LOCAL-GATES-PASSED
print "PASS: signed, notarized and stapled DMG plus signed appcast verified. Upload only ${OUTPUT}/public after clean-Mac acceptance. No upload performed."
