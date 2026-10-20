#!/bin/zsh
set -euo pipefail

# Prints only the selected identity to stdout so the build can consume it.
# This reads the keychain; it never creates certificates or changes trust settings.
SIGN_IDENTITY=${SUPERCLEANER_SIGN_IDENTITY:-}
REQUIRE_STABLE=${SUPERCLEANER_REQUIRE_STABLE_SIGNING:-0}
IDENTITIES=$(/usr/bin/security find-identity -v -p codesigning)

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
    print -u2 "Install an Apple Development or Developer ID Application certificate and its private key, then set SUPERCLEANER_SIGN_IDENTITY."
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

print -r -- "${SIGN_IDENTITY}"
