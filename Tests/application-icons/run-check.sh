#!/bin/zsh
set -euo pipefail
SCRIPT_DIR=${0:A:h}
cd ${SCRIPT_DIR:h:h}
swiftc -parse-as-library Sources/CleanerApp/ApplicationIconView.swift "${SCRIPT_DIR}/icon-contract.swift" -o "${SCRIPT_DIR}/icon-contract"
"${SCRIPT_DIR}/icon-contract"
