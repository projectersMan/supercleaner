#!/bin/zsh
set -euo pipefail

# Keep Apple's submission ID before polling. Re-running resumes that submission;
# an interrupted upload without a saved ID requires history reconciliation.
[[ $# == 2 ]] || { print -u2 'Usage: notarize-artifact.sh /absolute/artifact /absolute/evidence-directory'; exit 64; }
ARTIFACT=$1
EVIDENCE=$2
[[ ${ARTIFACT} == /* && -f ${ARTIFACT} && ! -L ${ARTIFACT} && ${EVIDENCE} == /* && ! -L ${EVIDENCE} ]] || { print -u2 'FAIL: regular artifact and evidence directory with absolute paths required'; exit 64; }
[[ -n ${SUPERCLEANER_NOTARY_PROFILE:-} ]] || { print -u2 'FAIL: SUPERCLEANER_NOTARY_PROFILE must name existing Keychain credentials'; exit 64; }
/bin/mkdir -p ${EVIDENCE}
for RECORD in artifact.sha256 submission.json status.json SUBMISSION-ATTEMPTED; do
  [[ ! -L ${EVIDENCE}/${RECORD} ]] || { print -u2 'FAIL: linked evidence refused'; exit 64; }
done
ARTIFACT_HASH=$(/usr/bin/shasum -a 256 ${ARTIFACT} | /usr/bin/awk '{print $1}')
if [[ -f ${EVIDENCE}/artifact.sha256 ]]; then
  [[ $(<${EVIDENCE}/artifact.sha256) == ${ARTIFACT_HASH} ]] || { print -u2 'FAIL: artifact changed; cannot reuse or overwrite this submission'; exit 65; }
else
  print -r -- ${ARTIFACT_HASH} > ${EVIDENCE}/artifact.sha256
fi
if [[ ! -f ${EVIDENCE}/submission.json ]]; then
  [[ ! -e ${EVIDENCE}/SUBMISSION-ATTEMPTED ]] || { print -u2 'FAIL: uncertain upload; reconcile notarytool history and recover its submission ID before continuing'; exit 75; }
  /usr/bin/touch ${EVIDENCE}/SUBMISSION-ATTEMPTED
  xcrun notarytool submit ${ARTIFACT} --keychain-profile "${SUPERCLEANER_NOTARY_PROFILE}" --output-format json > ${EVIDENCE}/submission.pending.json
  /usr/bin/plutil -extract id raw -o - ${EVIDENCE}/submission.pending.json > /dev/null
  /bin/mv ${EVIDENCE}/submission.pending.json ${EVIDENCE}/submission.json
fi
SUBMISSION_ID=$(/usr/bin/plutil -extract id raw -o - ${EVIDENCE}/submission.json)
[[ ${SUBMISSION_ID} =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$' ]] || { print -u2 'FAIL: invalid notarization submission ID'; exit 65; }
while true; do
  xcrun notarytool info ${SUBMISSION_ID} --keychain-profile "${SUPERCLEANER_NOTARY_PROFILE}" --output-format json > ${EVIDENCE}/status.pending.json
  /usr/bin/plutil -extract status raw -o - ${EVIDENCE}/status.pending.json > /dev/null
  /bin/mv ${EVIDENCE}/status.pending.json ${EVIDENCE}/status.json
  NOTARY_STATE=$(/usr/bin/plutil -extract status raw -o - ${EVIDENCE}/status.json)
  case ${NOTARY_STATE} in
    Accepted) print "PASS: Apple accepted ${SUBMISSION_ID}"; exit 0 ;;
    'In Progress') print "WAIT: Apple submission ${SUBMISSION_ID} remains in progress"; /bin/sleep 10 ;;
    Invalid|Rejected)
      xcrun notarytool log ${SUBMISSION_ID} --keychain-profile "${SUPERCLEANER_NOTARY_PROFILE}" --output-format json > ${EVIDENCE}/log.json
      print -u2 "FAIL: Apple returned ${NOTARY_STATE}; inspect ${EVIDENCE}/log.json"; exit 65 ;;
    *) print -u2 "FAIL: unrecognized notarization state ${NOTARY_STATE}; retained submission ${SUBMISSION_ID}, no resubmission"; exit 75 ;;
  esac
done
