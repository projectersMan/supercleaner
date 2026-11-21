#!/bin/zsh
set -euo pipefail

# Only a fully signed and verified pending file becomes the immutable input to
# notarization. A failed timestamp request leaves the pending file retryable.
[[ $# == 2 ]] || { print -u2 'Usage: sign-release-artifact.sh /absolute/pending.dmg /absolute/submitted.dmg'; exit 64; }
PENDING=$1
SUBMITTED=$2
[[ ${PENDING} == /* && ${SUBMITTED} == /* && ${PENDING:h} == ${SUBMITTED:h} && -f ${PENDING} && ! -L ${PENDING} && ! -e ${SUBMITTED} && ! -L ${SUBMITTED} ]] || { print -u2 'FAIL: regular pending artifact and a new same-directory submission path required'; exit 64; }
[[ -n ${SUPERCLEANER_SIGN_IDENTITY:-} && ${SUPERCLEANER_SIGN_IDENTITY} != - ]] || { print -u2 'FAIL: explicit Developer ID identity required'; exit 64; }
codesign --force --sign "${SUPERCLEANER_SIGN_IDENTITY}" --timestamp ${PENDING}
codesign --verify --strict --verbose=2 ${PENDING}
/bin/mv ${PENDING} ${SUBMITTED}
print 'PASS: signed artifact atomically committed for notarization'
