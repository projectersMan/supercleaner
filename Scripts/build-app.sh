#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
BUILD_ROOT=${PROJECT_ROOT}/build
APP=${BUILD_ROOT}/SuperCleaner.app
SCRATCH=${PROJECT_ROOT}/.build/release-scratch
CACHE=${PROJECT_ROOT}/.build/release-cache
CLANG_CACHE=${PROJECT_ROOT}/.build/release-clang-cache
AGENT_SCRATCH=${PROJECT_ROOT}/.build/agent-inference
DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
SIGN_IDENTITY=$(/bin/zsh "${SCRIPT_DIR}/signing-identity.sh")
SIGN_MODE=$(/bin/zsh "${SCRIPT_DIR}/signing-identity.sh" --mode)
BUNDLE_ID=${SUPERCLEANER_BUNDLE_ID:-com.example.SuperCleaner}
[[ ${BUNDLE_ID} =~ '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+){2,}$' ]] || { print -u2 "Invalid Bundle ID"; exit 1; }
HELPER_ID=${BUNDLE_ID}.helper
RELEASE_CONFIG=${SUPERCLEANER_RELEASE_CONFIG:-}
VERSION_VALUES=("${(@f)$(/usr/bin/python3 "${SCRIPT_DIR}/version.py" resolve)}")
DISPLAY_VERSION=${VERSION_VALUES[1]}
BUILD_NUMBER=${VERSION_VALUES[2]}
/usr/bin/python3 "${SCRIPT_DIR}/check-localizations.py"
MODEL_ASSET=${PROJECT_ROOT}/Sources/AgentOverlapAI/Resources/Models/embeddinggemma-2-Q8_0.gguf
[[ -f ${MODEL_ASSET} && ! -L ${MODEL_ASSET} ]] || { print -u2 "FAIL: bundled Agent model missing"; exit 1; }
[[ $(/usr/bin/stat -f %z ${MODEL_ASSET}) == 309855456 ]] || { print -u2 "FAIL: bundled Agent model size mismatch"; exit 1; }
[[ $(/usr/bin/shasum -a 256 ${MODEL_ASSET} | /usr/bin/awk '{print $1}') == 2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135 ]] || { print -u2 "FAIL: bundled Agent model checksum mismatch"; exit 1; }

if [[ ${DEVELOPER_DIR} == */CommandLineTools && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
else
  export SDKROOT=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
fi
export CLANG_MODULE_CACHE_PATH=${CLANG_CACHE}

AGENT_BUILD=(--package-path ${PROJECT_ROOT}/AgentInference --disable-sandbox --cache-path ${CACHE} --scratch-path ${AGENT_SCRATCH} --configuration release --arch arm64)
/usr/bin/swift build ${AGENT_BUILD[@]} --product AgentInference
AGENT_BIN_PATH=$(/usr/bin/swift build ${AGENT_BUILD[@]} --show-bin-path)

COMMON=(--disable-sandbox --cache-path ${CACHE} --scratch-path ${SCRATCH} --configuration release)
/usr/bin/swift build ${COMMON[@]} --product CoreContractChecks
BIN_PATH=$(/usr/bin/swift build ${COMMON[@]} --show-bin-path)
${BIN_PATH}/CoreContractChecks
${BIN_PATH}/CoreContractChecks --check-sparkle-release ${SCRATCH}/artifacts/sparkle/Sparkle/bin/sign_update
if [[ -n ${RELEASE_CONFIG} ]]; then
  [[ ${RELEASE_CONFIG} == /* ]] || { print -u2 "Release configuration path must be absolute"; exit 1; }
  ${BIN_PATH}/CoreContractChecks --validate-release-config ${RELEASE_CONFIG}
  CONFIG_BUNDLE_ID=$(/usr/bin/plutil -extract bundleIdentifier raw -o - ${RELEASE_CONFIG})
  if [[ -n ${SUPERCLEANER_BUNDLE_ID:-} && ${BUNDLE_ID} != ${CONFIG_BUNDLE_ID} ]]; then
    print -u2 "Bundle ID differs from release configuration"; exit 1
  fi
  BUNDLE_ID=${CONFIG_BUNDLE_ID}
  HELPER_ID=${BUNDLE_ID}.helper
fi

if [[ ${DEVELOPER_DIR} != */CommandLineTools && ${SUPERCLEANER_SKIP_XCTEST:-0} != 1 ]]; then
  /usr/bin/swift test ${COMMON[@]}
elif [[ ${SUPERCLEANER_SKIP_XCTEST:-0} == 1 ]]; then
  print "Skipping XCTest suite by request; CoreContractChecks have already passed."
fi

/usr/bin/swift build ${COMMON[@]} --product CleanerApp
/usr/bin/swift build ${COMMON[@]} --product CleanerHelper
/usr/bin/swift build ${COMMON[@]} --product supercleaner

[[ ${APP} == ${PROJECT_ROOT}/build/SuperCleaner.app && ! -L ${BUILD_ROOT} && ! -L ${APP} ]] || { print -u2 "Unsafe app output path"; exit 1; }
/bin/rm -rf -- ${APP}
/bin/mkdir -p ${APP}/Contents/MacOS ${APP}/Contents/Resources/Rules ${APP}/Contents/Frameworks ${APP}/Contents/Library/LaunchServices ${APP}/Contents/Library/LaunchDaemons
/bin/cp ${PROJECT_ROOT}/Resources/AppInfo.plist ${APP}/Contents/Info.plist
/bin/cp ${PROJECT_ROOT}/Resources/AppIcon.icns ${APP}/Contents/Resources/AppIcon.icns
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" ${APP}/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" ${APP}/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${DISPLAY_VERSION}" ${APP}/Contents/Info.plist
if [[ -n ${RELEASE_CONFIG} ]]; then
  /bin/cp ${RELEASE_CONFIG} ${APP}/Contents/Resources/release-configuration.json
  if APP_FEED=$(/usr/bin/plutil -extract applicationUpdateURL raw -o - ${RELEASE_CONFIG} 2>/dev/null); then
    APP_KEY=$(/usr/bin/plutil -extract applicationPublicKey raw -o - ${RELEASE_CONFIG})
    /usr/bin/plutil -insert SUFeedURL -string "${APP_FEED}" ${APP}/Contents/Info.plist
    /usr/bin/plutil -insert SUPublicEDKey -string "${APP_KEY}" ${APP}/Contents/Info.plist
  fi
fi
/usr/bin/ditto ${BIN_PATH}/Sparkle.framework ${APP}/Contents/Frameworks/Sparkle.framework
/bin/cp ${SCRATCH}/artifacts/sparkle/Sparkle/LICENSE ${APP}/Contents/Resources/Sparkle-LICENSE.txt
/bin/cp ${PROJECT_ROOT}/Sources/CleanerCore/Resources/base-rules.json ${APP}/Contents/Resources/Rules/base-rules.json
/bin/cp -R ${BIN_PATH}/SuperCleaner_CleanerCore.bundle ${APP}/Contents/Resources/
/bin/cp -R ${BIN_PATH}/SuperCleaner_AgentOverlapAI.bundle ${APP}/Contents/Resources/
/bin/cp -R ${AGENT_BIN_PATH}/GemmaEmbed_GemmaEmbed.bundle ${APP}/Contents/Resources/
/bin/cp ${AGENT_SCRATCH}/checkouts/gemma-embed-swift/LICENSE ${APP}/Contents/Resources/GemmaEmbed-LICENSE.txt
/bin/cp ${AGENT_BIN_PATH}/AgentInference ${APP}/Contents/MacOS/AgentInference
/bin/chmod 755 ${APP}/Contents/MacOS/AgentInference
/bin/cp ${PROJECT_ROOT}/Resources/HelperInfo.plist ${APP}/Contents/Resources/HelperInfo.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${HELPER_ID}" ${APP}/Contents/Resources/HelperInfo.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" ${APP}/Contents/Resources/HelperInfo.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${DISPLAY_VERSION}" ${APP}/Contents/Resources/HelperInfo.plist
/bin/cp -R ${PROJECT_ROOT}/Resources/en.lproj ${PROJECT_ROOT}/Resources/zh-Hans.lproj ${APP}/Contents/Resources/
/bin/cp ${PROJECT_ROOT}/Resources/LaunchDaemon.plist ${APP}/Contents/Library/LaunchDaemons/${HELPER_ID}.plist
DAEMON_PLIST=${APP}/Contents/Library/LaunchDaemons/${HELPER_ID}.plist
/usr/libexec/PlistBuddy -c "Set :Label ${HELPER_ID}" ${DAEMON_PLIST}
/usr/libexec/PlistBuddy -c "Set :BundleProgram Contents/Library/LaunchServices/${HELPER_ID}" ${DAEMON_PLIST}
/usr/libexec/PlistBuddy -c 'Delete :MachServices' ${DAEMON_PLIST}
/usr/libexec/PlistBuddy -c 'Add :MachServices dict' ${DAEMON_PLIST}
/usr/libexec/PlistBuddy -c "Add :MachServices:${HELPER_ID} bool true" ${DAEMON_PLIST}
/usr/libexec/PlistBuddy -c "Set :AssociatedBundleIdentifiers:0 ${BUNDLE_ID}" ${DAEMON_PLIST}
/bin/cp ${BIN_PATH}/CleanerApp ${APP}/Contents/MacOS/CleanerApp
/bin/cp ${BIN_PATH}/supercleaner ${APP}/Contents/MacOS/supercleaner
/bin/cp ${BIN_PATH}/CleanerHelper ${APP}/Contents/Library/LaunchServices/${HELPER_ID}
/bin/chmod 755 ${APP}/Contents/MacOS/CleanerApp ${APP}/Contents/MacOS/supercleaner ${APP}/Contents/Library/LaunchServices/${HELPER_ID}

SIGN_OPTIONS=(--force --sign "${SIGN_IDENTITY}")
if [[ ${SIGN_MODE} != apple ]]; then
  # Local certificates have no Apple team identity or timestamp service.
  # Production gates still require Developer ID, runtime and timestamps.
  SIGN_OPTIONS+=(--options 0 --timestamp=none)
else
  SIGN_OPTIONS+=(--options runtime --timestamp)
fi
# Sign inside-out without --deep; retain Sparkle's sandbox/network entitlements.
SPARKLE=${APP}/Contents/Frameworks/Sparkle.framework/Versions/B
for XPC in ${SPARKLE}/XPCServices/*.xpc(N); do
  /usr/bin/codesign ${SIGN_OPTIONS[@]} --preserve-metadata=entitlements ${XPC}
done
/usr/bin/codesign ${SIGN_OPTIONS[@]} ${SPARKLE}/Autoupdate
/usr/bin/codesign ${SIGN_OPTIONS[@]} ${SPARKLE}/Updater.app
/usr/bin/codesign ${SIGN_OPTIONS[@]} ${APP}/Contents/Frameworks/Sparkle.framework
/usr/bin/codesign ${SIGN_OPTIONS[@]} --identifier ${HELPER_ID} ${APP}/Contents/Library/LaunchServices/${HELPER_ID}
/usr/bin/codesign ${SIGN_OPTIONS[@]} --identifier ${BUNDLE_ID}.cli ${APP}/Contents/MacOS/supercleaner
/usr/bin/codesign ${SIGN_OPTIONS[@]} --identifier ${BUNDLE_ID}.agent-inference ${APP}/Contents/MacOS/AgentInference
/usr/bin/codesign ${SIGN_OPTIONS[@]} --identifier ${BUNDLE_ID} ${APP}
${BIN_PATH}/CoreContractChecks --check-cli ${APP}/Contents/MacOS/supercleaner
${BIN_PATH}/CoreContractChecks --check-cli-config ${APP}/Contents/MacOS/supercleaner
HELPER_EXPECTED_EXIT=0
if [[ ${SIGN_MODE} != apple || ${BUNDLE_ID} == com.example.* ]]; then HELPER_EXPECTED_EXIT=78; fi
${BIN_PATH}/CoreContractChecks --check-helper-identity ${APP}/Contents/Library/LaunchServices/${HELPER_ID} ${HELPER_EXPECTED_EXIT}
${BIN_PATH}/CoreContractChecks --check-production-gate ${APP} ${SCRIPT_DIR}/check-production-signing.sh
if [[ ${SIGN_IDENTITY} == - ]]; then
  print "Signing: ad-hoc development identity (permissions may reset after rebuild)"
else
  print "Signing: ${SIGN_IDENTITY}"
fi
print "Built ${APP}"
