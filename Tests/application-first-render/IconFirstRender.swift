import AppKit
import Foundation
import SwiftUI

@main enum IconFirstRender {
    @MainActor static func main() {
        _ = NSApplication.shared
        let owner = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let names = ["WorkBuddy Helper.app", "WorkBuddy Helper (GPU).app", "WorkBuddy Helper (Plugin).app",
            "WorkBuddy Helper (Renderer).app", "WorkBuddy Legacy Auto Launch Cleaner.app",
            "WorkBuddy 文件浏览器.app/Contents/Frameworks/WorkBuddy 文件浏览器 Helper (GPU).app"]
        let helpers = names.map { owner.appendingPathComponent("Contents/Frameworks/" + $0) }
        guard helpers.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            FileHandle.standardError.write(Data("SKIP: installed WorkBuddy helper fixture unavailable\n".utf8))
            exit(77)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 640),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: AnyView(Color.clear))
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let start = Date()
        view.rootView = AnyView(VStack {
            ForEach(helpers, id: \.self) { helper in
                ApplicationIconView(bundleURL: helper, version: "1")
            }
        })
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let elapsed = Date().timeIntervalSince(start)
        FileHandle.standardOutput.write(Data("Nested helper first render: six cold icons, actual SwiftUI layout = \(elapsed)s\n".utf8))
        guard elapsed < 0.15 else {
            FileHandle.standardError.write(Data("FAIL: cold helper icon rendering exceeds the 150 ms main-thread budget\n".utf8))
            exit(1)
        }
        print("PASS: cold helper rendering stays within the 150 ms budget")
    }
}
