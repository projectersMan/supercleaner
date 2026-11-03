#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h}
PROJECT=${ROOT:h:h}
IDENTITY=$(/bin/zsh ${PROJECT}/Scripts/signing-identity.sh)
[[ ${IDENTITY} != - ]] || { print -u2 'FAIL: fixed certificate required'; exit 1; }
WORK=$(/usr/bin/mktemp -d ${ROOT}/fixtures.XXXXXX)
cleanup() { [[ ${WORK:h} == ${ROOT} && ${WORK:t} == fixtures.* ]] && /bin/rm -rf -- ${WORK}; }
trap cleanup EXIT INT TERM
export TMPDIR=${WORK}
print 'int main(void) { return 0; }' > ${WORK}/first.c
print 'int main(void) { return 1; }' > ${WORK}/second.c
/usr/bin/clang ${WORK}/first.c -o ${WORK}/first
/usr/bin/clang ${WORK}/second.c -o ${WORK}/second
for BINARY in first second; do
  /usr/bin/codesign --force --sign ${IDENTITY} --options 0 --timestamp=none --identifier com.example.SuperCleaner.signing-fixture ${WORK}/${BINARY}
  /usr/bin/codesign -d -r- ${WORK}/${BINARY} 2>&1 | /usr/bin/sed -n 's/^designated => //p' > ${WORK}/${BINARY}.requirement
done
! /usr/bin/cmp -s ${WORK}/first ${WORK}/second || { print -u2 'FAIL: fixtures must differ'; exit 1; }
/usr/bin/cmp ${WORK}/first.requirement ${WORK}/second.requirement
REQUIREMENT=$(<${WORK}/first.requirement)
[[ ( ${REQUIREMENT} == *'anchor '* || ${REQUIREMENT} == *'certificate leaf = H"'* ) && ${REQUIREMENT} != *'cdhash '* ]] || { print -u2 'FAIL: certificate-bound DR required'; exit 1; }
/usr/bin/codesign --verify --strict -R=${REQUIREMENT} ${WORK}/second
/usr/bin/codesign --force --sign - --identifier com.example.SuperCleaner.signing-fixture ${WORK}/second
if /usr/bin/codesign --verify --strict -R=${REQUIREMENT} ${WORK}/second >/dev/null 2>&1; then
  print -u2 'FAIL: matching Bundle ID without the certificate must be rejected'
  exit 1
fi
print "PASS: different binaries share certificate-bound DR; old DR accepts new binary; ad-hoc replacement rejected; certificate ${IDENTITY}"
