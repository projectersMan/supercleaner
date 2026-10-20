#!/bin/zsh
set -euo pipefail

APP=${1:-}
OUTPUT=${2:-}
SCRIPT_DIR=${0:A:h}

[[ -n ${APP} && -n ${OUTPUT} ]] || { print -u2 "Usage: create-dmg.sh /absolute/path/SuperCleaner.app /absolute/path/SuperCleaner.dmg"; exit 1; }
[[ ${APP} == /* && ${OUTPUT} == /* ]] || { print -u2 "FAIL: app and output paths must be absolute"; exit 1; }
[[ -d ${APP} && ! -L ${APP} && ${APP:e:l} == app ]] || { print -u2 "FAIL: source must be a regular .app bundle"; exit 1; }
[[ ${OUTPUT:e:l} == dmg && ! -e ${OUTPUT} && ! -L ${OUTPUT} ]] || { print -u2 "FAIL: output must be a new .dmg path"; exit 1; }
[[ -d ${OUTPUT:h} && ! -L ${OUTPUT:h} ]] || { print -u2 "FAIL: output parent must be an existing regular directory"; exit 1; }

STAGING=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/supercleaner-dmg.XXXXXX")
MOUNT_POINT=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/supercleaner-dmg-mount.XXXXXX")
WORK=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/supercleaner-dmg-work.XXXXXX")
APP_NAME=${APP:t:r}
RW_IMAGE=${WORK}/${APP_NAME}-rw.dmg
MOUNTED=0
SUCCESS=0
cleanup() {
  if (( MOUNTED )); then
    /usr/bin/hdiutil detach -quiet ${MOUNT_POINT} >/dev/null 2>&1 || true
  fi
  if [[ -n ${STAGING:-} && -d ${STAGING} && ${STAGING:t} == supercleaner-dmg.* ]]; then
    /bin/rm -rf -- ${STAGING}
  fi
  if [[ -n ${MOUNT_POINT:-} && -d ${MOUNT_POINT} && ${MOUNT_POINT:t} == supercleaner-dmg-mount.* ]]; then
    /bin/rmdir ${MOUNT_POINT} >/dev/null 2>&1 || true
  fi
  if [[ -n ${WORK:-} && -d ${WORK} && ${WORK:t} == supercleaner-dmg-work.* ]]; then
    /bin/rm -rf -- ${WORK}
  fi
  if (( ! SUCCESS )) && [[ -f ${OUTPUT} && ! -L ${OUTPUT} ]]; then
    /bin/rm -f -- ${OUTPUT}
  fi
}
trap cleanup EXIT INT TERM

/usr/bin/ditto ${APP} ${STAGING}/${APP_NAME}.app
/bin/ln -s /Applications ${STAGING}/Applications
/bin/cp ${APP}/Contents/Resources/AppIcon.icns ${STAGING}/.VolumeIcon.icns
/usr/bin/hdiutil create -fs HFS+ -format UDRW -volname ${APP_NAME} -srcfolder ${STAGING} ${RW_IMAGE}
/usr/bin/hdiutil attach -quiet -nobrowse -mountpoint ${MOUNT_POINT} ${RW_IMAGE}
MOUNTED=1
/usr/bin/SetFile -a C ${MOUNT_POINT}
/usr/bin/hdiutil detach -quiet ${MOUNT_POINT}
MOUNTED=0
/usr/bin/hdiutil convert ${RW_IMAGE} -format UDZO -o ${OUTPUT} >/dev/null
/usr/bin/swift ${SCRIPT_DIR}/set-file-icon.swift ${APP}/Contents/Resources/AppIcon.icns ${OUTPUT}
/usr/bin/hdiutil imageinfo ${OUTPUT} >/dev/null
[[ $(/usr/bin/GetFileInfo -a ${OUTPUT}) == *C* ]] || { print -u2 "FAIL: DMG file custom icon flag is not set"; exit 1; }
/usr/bin/hdiutil attach -quiet -readonly -nobrowse -mountpoint ${MOUNT_POINT} ${OUTPUT}
MOUNTED=1
[[ -d ${MOUNT_POINT}/${APP_NAME}.app && ! -L ${MOUNT_POINT}/${APP_NAME}.app ]] || { print -u2 "FAIL: DMG is missing ${APP_NAME}.app"; exit 1; }
[[ -L ${MOUNT_POINT}/Applications && $(/usr/bin/readlink ${MOUNT_POINT}/Applications) == /Applications ]] || { print -u2 "FAIL: DMG is missing the /Applications shortcut"; exit 1; }
[[ -f ${MOUNT_POINT}/.VolumeIcon.icns ]] || { print -u2 "FAIL: DMG is missing its volume icon"; exit 1; }
/usr/bin/GetFileInfo -a ${MOUNT_POINT} | /usr/bin/grep -q 'C' || { print -u2 "FAIL: DMG volume custom icon flag is not set"; exit 1; }
/usr/bin/codesign --verify --deep --strict --all-architectures ${MOUNT_POINT}/${APP_NAME}.app
/usr/bin/hdiutil detach -quiet ${MOUNT_POINT}
MOUNTED=0
SUCCESS=1

print "PASS: created drag-to-Applications disk image with the app icon at ${OUTPUT}"
