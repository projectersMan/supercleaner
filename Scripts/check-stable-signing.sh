#!/bin/zsh
set -euo pipefail

APP=${1:-}
[[ $# == 1 && -d ${APP} && ! -L ${APP} && ${APP:e:l} == app ]] || {
  print -u2 'Usage: check-stable-signing.sh /path/to/App.app'; exit 1
}
/usr/bin/codesign --verify --deep --strict --all-architectures ${APP}
SIGNATURE=$(/usr/bin/codesign -dv ${APP} 2>&1)
REQUIREMENT=$(/usr/bin/codesign -d -r- ${APP} 2>&1)
if [[ ${SIGNATURE} == *'Signature=adhoc'* || ${REQUIREMENT} == *'cdhash '* ]]; then
  print -u2 'FAIL: certificate-bound signing is required; ad-hoc apps cannot be packaged'
  exit 1
fi
[[ ${REQUIREMENT} == *'anchor '* || ${REQUIREMENT} == *'certificate leaf = H"'* ]] || {
  print -u2 'FAIL: stable certificate-bound identity required'; exit 1
}
print 'PASS: certificate-bound signing identity verified'
