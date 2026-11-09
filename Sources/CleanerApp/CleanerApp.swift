import AppKit
import CleanerCore
import Foundation
import SwiftUI

@main enum CleanerMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--scan-cleanup-self-check") {
            Task { @MainActor in
                do {
                    try AppModel.checkConcurrentScanCleanup()
                    if let fixture = ProcessInfo.processInfo.environment["SUPERCLEANER_DUPLICATE_FIXTURE"] {
                        try await AppModel.checkDuplicateLargeFileSelection(home: URL(fileURLWithPath: fixture))
                    }
                    exit(0)
                } catch { FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8)); exit(1) }
            }
            dispatchMain()
        } else if CommandLine.arguments.contains("--preferences-self-check") {
            let expected = L10n.language == .english ? "Settings" : "设置"
            guard L10n.text("设置") == expected,
                  AppVersion.current.build != "—",
                  AppVersion.current.build != "0",
                  Bundle.main.localizations.contains("en"),
                  Bundle.main.localizations.contains("zh-Hans") else {
                FileHandle.standardError.write(Data("FAIL: packaged language/version metadata\n".utf8))
                exit(1)
            }
            print("PASS: preferences \(L10n.language.rawValue), version \(AppVersion.current.version) (\(AppVersion.current.build))")
            exit(0)
        } else if CommandLine.arguments.contains("--update-self-check") {
            do { try ApplicationUpdateModel.selfCheck(requireProduction: CommandLine.arguments.contains("--require-production-updater")); exit(0) }
            catch { FileHandle.standardError.write(Data("FAIL: application update self-check\n".utf8)); exit(1) }
        } else if CommandLine.arguments.contains("--smoke-test") {
            Task.detached {
                do { try await CleanerSmokeTest.run(); print("PASS: smoke cleanup and restore"); exit(0) }
                catch { FileHandle.standardError.write(Data("FAIL: smoke test: \(error)\n".utf8)); exit(1) }
            }
            dispatchMain()
        } else {
            // AppKit and embedded update windows use the same language on next launch.
            UserDefaults.standard.set([L10n.language.rawValue], forKey: "AppleLanguages")
            CleanerGUI.main()
        }
    }
}

struct CleanerGUI: App {
    @NSApplicationDelegateAdaptor(CleanerApplicationDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowContent(delegate: delegate)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 820)
    }
}

struct MainWindowContent: View {
    @Environment(\.openWindow) private var openWindow
    let delegate: CleanerApplicationDelegate

    var body: some View {
        ContentView()
            .environment(\.locale, L10n.language.locale)
            .onAppear {
                delegate.reopenMainWindow = { openWindow(id: "main") }
            }
    }
}

@MainActor final class CleanerApplicationDelegate: NSObject, NSApplicationDelegate {
    var reopenMainWindow: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        let miniaturizedWindows = sender.windows.filter(\.isMiniaturized)
        if !miniaturizedWindows.isEmpty {
            for window in miniaturizedWindows {
                window.deminiaturize(nil)
            }
            return false
        }

        guard !hasVisibleWindows else { return true }
        reopenMainWindow?()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Sparkle can install a prepared update on quit. Keep that path closed
        // until the final explicit approval, or until cancellation has finished.
        ApplicationUpdateTerminationGuard.allowsTermination ? .terminateNow : .terminateCancel
    }
}
