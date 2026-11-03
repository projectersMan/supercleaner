#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
cd ${SCRIPT_DIR:h:h}
swift build --product CleanerApp
BIN_PATH=$(swift build --show-bin-path)
swiftc -parse-as-library -I "${BIN_PATH}" "${SCRIPT_DIR}/analysis-contract.swift" "${BIN_PATH}/CleanerCore.o" "${BIN_PATH}/AgentOverlapAI.o" -o "${SCRIPT_DIR}/analysis-contract"
PACKAGE_RESOURCE_BUNDLE_PATH="${BIN_PATH}" "${SCRIPT_DIR}/analysis-contract"
swiftc -parse-as-library -I "${BIN_PATH}" "${SCRIPT_DIR}/label-contract.swift" Sources/CleanerApp/AgentContainmentLabel.swift "${BIN_PATH}/CleanerCore.o" -o "${SCRIPT_DIR}/label-contract"
PACKAGE_RESOURCE_BUNDLE_PATH="${BIN_PATH}" "${SCRIPT_DIR}/label-contract" "${SCRIPT_DIR}/status.png"
PACKAGE_RESOURCE_BUNDLE_PATH="${BIN_PATH}" "${SCRIPT_DIR}/label-contract" "${SCRIPT_DIR}/top-three.png" "${SCRIPT_DIR}/fixtures/index.plist"
