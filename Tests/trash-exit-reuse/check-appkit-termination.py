from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]
QA = Path(__file__).resolve().parent
source = (ROOT / 'Sources/CleanerApp/CleanerApp.swift').read_text()
delegate = source[source.index('@MainActor final class CleanerApplicationDelegate:'):]
probe = '''import AppKit
import Foundation

// Only the cleanup dependency is synthetic; the delegate below is copied verbatim.
@MainActor final class AppModel {
    var trashEmptyingInProgress = false
}
enum ApplicationUpdateTerminationGuard {
    static let allowsTermination = true
}
@MainActor final class TrashReminderController {
    var isEmptyingTrash = false
    init(preferences: UserDefaults) {}
    func remindIfNeeded(model: AppModel, isQuitting: Bool) -> Task<Bool, Never>? {
        FileHandle.standardError.write(Data("probe: reminder called\\n".utf8))
        isEmptyingTrash = true
        return Task {
            FileHandle.standardError.write(Data("probe: executor task started\\n".utf8))
            await Task.yield()
            FileHandle.standardError.write(Data("probe: executor task resumed\\n".utf8))
            isEmptyingTrash = false
            print("PASS: asynchronous cleanup dependency completed before AppKit quit")
            return true
        }
    }
}
@main enum AppKitTerminationProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = CleanerApplicationDelegate()
        let model = AppModel()
        delegate.model = model
        app.delegate = delegate
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                FileHandle.standardError.write(Data("probe: native termination event started\\n".utf8))
                app.terminate(nil)
            }
        }
        FileHandle.standardError.write(Data("probe: starting native run loop\\n".utf8))
        withExtendedLifetime((delegate, model)) { app.run() }
    }
}

'''
path = QA / 'AppKitTerminationProbe.swift'
path.write_text(probe + delegate)
subprocess.run(['/usr/bin/xcrun', 'swiftc', '-parse-as-library', '-swift-version', '6', str(path),
                '-o', str(QA / 'AppKitTerminationProbe')], check=True)
result = subprocess.run([str(QA / 'AppKitTerminationProbe')], text=True, timeout=20, stdout=(QA / 'appkit-probe.stdout').open('w'), stderr=(QA / 'appkit-probe.stderr').open('w'))
result.stdout = (QA / 'appkit-probe.stdout').read_text()
result.stderr = (QA / 'appkit-probe.stderr').read_text()
print(result.stdout, end='')
print(result.stderr, end='')
assert result.returncode == 0, result.returncode
assert 'PASS: asynchronous cleanup dependency completed before AppKit quit' in result.stdout
(QA / 'appkit-delegate-hash.json').write_text(json.dumps({'sha256': hashlib.sha256(delegate.encode()).hexdigest()}, indent=2) + '\n')
print('PASS: verbatim production delegate waits through the real NSApplication terminateLater/reply loop; no Finder or user cleanup')
