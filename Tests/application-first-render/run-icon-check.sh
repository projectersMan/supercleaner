#!/bin/zsh
set -euo pipefail
task_root=${0:A:h:h:h}
task_output=${task_root}/Tests/application-first-render
task_source=${1:?ApplicationIconView.swift source path required}
CLANG_MODULE_CACHE_PATH=${task_root}/.build/release-clang-cache /usr/bin/swiftc -O -swift-version 6 -parse-as-library \
    "$task_source" "${task_output}/IconFirstRender.swift" \
    -o "${task_output}/IconFirstRender"
"${task_output}/IconFirstRender" /Applications/WorkBuddy.app
