#!/bin/zsh
set -euo pipefail

# Prints only the selected identity to stdout so the build can consume it.
# This reads the keychain; it never creates certificates or changes trust settings.
SIGN_IDENTITY=${SUPERCLEANER_SIGN_IDENTITY:-}
REQUIRE_STABLE=${SUPERCLEANER_REQUIRE_STABLE_SIGNING:-1}
IDENTITY_FILE=${SUPERCLEANER_SIGN_IDENTITY_FILE:-${HOME}/Library/Application Support/SuperCleaner/Signing/identity.sha1}
IDENTITIES=$(/usr/bin/security find-identity -v -p codesigning)

if [[ -z ${SIGN_IDENTITY} && -f ${IDENTITY_FILE} ]]; then
  [[ ! -L ${IDENTITY_FILE} ]] || { print -u2 "Signing identity file must be a regular file."; exit 1; }
  SIGN_IDENTITY=$(<${IDENTITY_FILE})
  [[ ${SIGN_IDENTITY} =~ '^[0-9A-Fa-f]{40}$' ]] || { print -u2 "Signing identity file must contain one certificate SHA-1."; exit 1; }
fi
if [[ -z ${SIGN_IDENTITY} ]]; then
  SIGN_IDENTITY=$(print -r -- "${IDENTITIES}" | /usr/bin/awk '/"Developer ID Application:/ { print $2; exit }')
  if [[ -z ${SIGN_IDENTITY} ]]; then
    SIGN_IDENTITY=$(print -r -- "${IDENTITIES}" | /usr/bin/awk '/"Apple Development:/ { print $2; exit }')
  fi
  SIGN_IDENTITY=${SIGN_IDENTITY:--}
fi

if [[ ${SIGN_IDENTITY} == - ]]; then
  if [[ ${REQUIRE_STABLE} == 1 ]]; then
    print -u2 "Cannot build with a stable identity: no signing certificate is configured."
    print -u2 "Configure a fixed local development or Apple signing certificate and private key, then pin its SHA-1 with SUPERCLEANER_SIGN_IDENTITY or ${IDENTITY_FILE}."
    exit 1
  fi
  print -u2 "Development build uses ad-hoc signing: rebuilding can invalidate previous macOS privacy permissions."
  print -u2 "For stable permissions, install a signing certificate and use SUPERCLEANER_REQUIRE_STABLE_SIGNING=1."
else
  MATCH=$(print -r -- "${IDENTITIES}" | /usr/bin/awk -v requested="${SIGN_IDENTITY}" '
    /"/ {
      name = $0; sub(/^[^"]*"/, "", name); sub(/".*$/, "", name)
      if ($2 == requested || name == requested) { print $2; exit }
    }')
  if [[ -z ${MATCH} ]]; then
    print -u2 "Configured signing certificate is unavailable or has no usable private key."
    print -u2 "Install the certificate and its private key before rebuilding."
    exit 1
  fi
  SIGN_IDENTITY=${MATCH}
fi

if [[ ${1:-} == --mode ]]; then
  if [[ ${SIGN_IDENTITY} == - ]]; then
    print ad-hoc
  else
    NAME=$(print -r -- "${IDENTITIES}" | /usr/bin/awk -v requested="${SIGN_IDENTITY}" '$2 == requested { sub(/^[^"]*"/, ""); sub(/".*$/, ""); print; exit }')
    if [[ ${NAME} == 'Developer ID Application:'* || ${NAME} == 'Apple Development:'* ]]; then
      print apple
    else
      print local-development
    fi
  fi
elif [[ $# == 0 ]]; then
  print -r -- "${SIGN_IDENTITY}"
else
  print -u2 "Usage: signing-identity.sh [--mode]"
  exit 1
fi
