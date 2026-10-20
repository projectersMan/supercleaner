import AppKit
import Foundation
import SwiftUI

@main enum CleanerMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--update-self-check") {
            do { try ApplicationUpdateModel.selfCheck(requireProduction: CommandLine.arguments.contains("--require-production-updater")); exit(0) }
            catch { FileHandle.standardError.write(Data("FAIL: application update self-check\n".utf8)); exit(1) }
        } else if CommandLine.arguments.contains("--smoke-test") {
            Task.detached {
                do { try await CleanerSmokeTest.run(); print("PASS: smoke cleanup and restore"); exit(0) }
                catch { FileHandle.standardError.write(Data("FAIL: smoke test: \(error)\n".utf8)); exit(1) }
            }
            dispatchMain()
        } else {
            CleanerGUI.main()
        }
    }
}

struct CleanerGUI: App {
    @NSApplicationDelegateAdaptor(CleanerApplicationDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1280, height: 820)
    }
}

@MainActor final class CleanerApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Sparkle can install a prepared update on quit. Keep that path closed
        // until the final explicit approval, or until cancellation has finished.
        ApplicationUpdateTerminationGuard.allowsTermination ? .terminateNow : .terminateCancel
    }
}
