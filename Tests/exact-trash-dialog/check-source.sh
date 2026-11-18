#!/bin/zsh
set -euo pipefail

PROJECT_ROOT=${0:A:h:h:h}
CONTROLLER=${PROJECT_ROOT}/Sources/CleanerApp/TrashReminderController.swift
OBSERVER=${PROJECT_ROOT}/Sources/CleanerApp/TrashReminderWindowObserver.swift
APPLICATION=${PROJECT_ROOT}/Sources/CleanerApp/CleanerApp.swift
DASHBOARD=${PROJECT_ROOT}/Sources/CleanerApp/DashboardView.swift

# The close-only checkbox is intentional. Both presentations must still use
# one factory and one executor, with no separate quit decision or alert clone.
if rg -n 'TrashEmptyingContext|TrashEmptyingDecision|直接关闭|继续退出|取消退出' ${CONTROLLER}; then
    print -u2 'FAIL: obsolete quit choices or context remain'
    exit 1
fi
rg -q 'private let confirmEmptyTrash: @MainActor \(Bool\) -> TrashEmptyingConfirmation' ${CONTROLLER}
rg -q 'static func makeEmptyingAlert\(showsSuppressionOption: Bool\)' ${CONTROLLER}
if rg -n 'allowsEmptying|\.isEnabled\s*=' ${CONTROLLER}; then
    print -u2 'FAIL: displayed confirmation must not contain a disabled Empty Trash branch'
    exit 1
fi
rg -q 'alert.showsSuppressionButton = showsSuppressionOption' ${CONTROLLER}
rg -q 'requestEmptyTrash\(model: model, showsSuppressionOption: false\)' ${CONTROLLER}
rg -q 'requestEmptyTrash\(model: model, showsSuppressionOption: true\)' ${CONTROLLER}
rg -q 'trashReminder.requestEmptyTrash\(model: model\)' ${DASHBOARD}
rg -q 'controller\?\.remindAfterWindowClose\(model: model\)' ${OBSERVER}
rg -q 'self.remindAfterWindowClose\(model: model\)' ${CONTROLLER}
rg -q 'return requestEmptyTrash\(model: model\)' ${CONTROLLER}
rg -q 'trashReminder.remindIfNeeded\(model: model\)' ${APPLICATION}
if rg -n '\.delegate\s*=' ${OBSERVER}; then
    print -u2 'FAIL: window observer must preserve the SwiftUI window delegate'
    exit 1
fi
print 'PASS: one factory and executor; suppression is close-only, manual confirmation unchanged; observer preserves window delegate'
