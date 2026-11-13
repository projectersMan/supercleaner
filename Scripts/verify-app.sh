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
CORE_BUNDLE=${APP}/Contents/Resources/SuperCleaner_CleanerCore.bundle
[[ -f ${CORE_BUNDLE}/base-rules.json || -f ${CORE_BUNDLE}/Contents/Resources/base-rules.json ]] || { print -u2 "FAIL: SwiftPM CleanerCore resource bundle missing"; exit 1; }
[[ -f ${APP}/Contents/Resources/Sparkle-LICENSE.txt && -f ${APP}/Contents/Frameworks/Sparkle.framework/Sparkle ]] || { print -u2 "FAIL: embedded updater missing"; exit 1; }

MODEL_ASSET=${APP}/Contents/Resources/SuperCleaner_AgentOverlapAI.bundle/Contents/Resources/Models/embeddinggemma-2-Q8_0.gguf
if [[ ! -f ${MODEL_ASSET} ]]; then
  MODEL_ASSET=${APP}/Contents/Resources/SuperCleaner_AgentOverlapAI.bundle/Models/embeddinggemma-2-Q8_0.gguf
fi
[[ -f ${MODEL_ASSET} && ! -L ${MODEL_ASSET} ]] || { print -u2 "FAIL: bundled Agent model missing"; exit 1; }
[[ $(/usr/bin/stat -f %z ${MODEL_ASSET}) == 309855456 ]] || { print -u2 "FAIL: bundled Agent model size mismatch"; exit 1; }
[[ $(/usr/bin/shasum -a 256 ${MODEL_ASSET} | /usr/bin/awk '{print $1}') == 2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135 ]] || { print -u2 "FAIL: bundled Agent model checksum mismatch"; exit 1; }
[[ -f ${MODEL_ASSET:h}/LICENSE.txt && -f ${MODEL_ASSET:h}/NOTICE.txt && -f ${APP}/Contents/Resources/GemmaEmbed-LICENSE.txt ]] || { print -u2 "FAIL: Agent license notices missing"; exit 1; }
[[ -x ${APP}/Contents/MacOS/AgentInference && -d ${APP}/Contents/Resources/GemmaEmbed_GemmaEmbed.bundle ]] || { print -u2 "FAIL: Agent inference runtime missing"; exit 1; }
/usr/bin/codesign --verify --strict ${APP}/Contents/MacOS/AgentInference

for KEY in CFBundleVersion CFBundleShortVersionString; do
  [[ $(/usr/libexec/PlistBuddy -c "Print :${KEY}" ${APP}/Contents/Info.plist) == $(/usr/libexec/PlistBuddy -c "Print :${KEY}" ${APP}/Contents/Resources/HelperInfo.plist) ]] || { print -u2 "FAIL: app/helper version mismatch"; exit 1; }
done
for LANGUAGE in en zh-Hans; do
  [[ -f ${APP}/Contents/Resources/${LANGUAGE}.lproj/InfoPlist.strings ]] || { print -u2 "FAIL: missing native language resource"; exit 1; }
  ${APP}/Contents/MacOS/CleanerApp --preferences-self-check -appLanguage ${LANGUAGE}
done

MINIMUM=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' ${APP}/Contents/Info.plist)
[[ ${MINIMUM} == 13.0 ]] || { print -u2 "FAIL: minimum macOS is ${MINIMUM}"; exit 1; }
/usr/bin/codesign --verify --deep --strict --verbose=2 ${APP}
if [[ ${SUPERCLEANER_REQUIRE_STABLE_SIGNING:-1} == 1 ]]; then
  SIGNATURE=$(/usr/bin/codesign -dv ${APP} 2>&1)
  if [[ ${SIGNATURE} == *"Signature=adhoc"* ]]; then
    print -u2 "FAIL: a certificate-signed app is required for stable privacy authorization across builds"
    exit 1
  fi
  REQUIREMENT=$(/usr/bin/codesign -d -r- ${APP} 2>&1)
  [[ ( ${REQUIREMENT} == *"anchor "* || ${REQUIREMENT} == *'certificate leaf = H"'* ) && ${REQUIREMENT} != *"cdhash "* ]] || { print -u2 "FAIL: stable certificate-bound identity required"; exit 1; }
fi
${APP}/Contents/MacOS/CleanerApp --smoke-test
${APP}/Contents/MacOS/CleanerApp --update-self-check
"${APP}/Contents/MacOS/CleanerApp" --scan-cleanup-self-check
"${APP}/Contents/MacOS/CleanerApp" --cleanup-completion-self-check
"${APP}/Contents/MacOS/CleanerApp" --uninstall-permission-self-check
"${APP}/Contents/MacOS/CleanerApp" --scan-permission-presentation-self-check
"${APP}/Contents/MacOS/CleanerApp" --navigation-presentation-self-check
"${APP}/Contents/MacOS/CleanerApp" --application-responsiveness-self-check
"${APP}/Contents/MacOS/CleanerApp" --agent-presentation-self-check
print "PASS: SuperCleaner.app structure, signature, smoke flow, and concurrent scan cleanup verified"
