import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

@main struct IconContract {
    @MainActor static func main() throws {
        let parent = URL(fileURLWithPath: "/Applications/WorkBuddy.app")
        let fileBrowser = parent.appendingPathComponent("Contents/Frameworks/WorkBuddy 文件浏览器.app")
        guard FileManager.default.fileExists(atPath: parent.path) else {
            print("SKIP: this targeted check requires the installed WorkBuddy fixture")
            exit(77)
        }
        guard let parentIcon = NSWorkspace.shared.icon(forFile: parent.path).tiffRepresentation,
              let browserIcon = NSWorkspace.shared.icon(forFile: fileBrowser.path).tiffRepresentation else {
            print("FAIL: fixture icon data unavailable")
            exit(1)
        }
        var passed = true
        for name in ["WorkBuddy Helper.app", "WorkBuddy Helper (GPU).app", "WorkBuddy Helper (Plugin).app", "WorkBuddy Helper (Renderer).app", "WorkBuddy Legacy Auto Launch Cleaner.app"] {
            let url = parent.appendingPathComponent("Contents/Frameworks/\(name)")
            let icon = ApplicationIconCache.shared.icon(for: url, version: nil)
            let matches = icon.tiffRepresentation == parentIcon
            print(matches ? "PASS: \(name) inherits owner icon" : "FAIL: \(name) still has a placeholder")
            passed = passed && matches
        }
        let own = ApplicationIconCache.shared.icon(for: fileBrowser, version: nil).tiffRepresentation
        let browserPreserved = own == browserIcon && own != parentIcon
        print(browserPreserved ? "PASS: nested File Browser keeps its independent icon" : "FAIL: independent icon replaced")
        let browserHelper = fileBrowser.appendingPathComponent("Contents/Frameworks/WorkBuddy 文件浏览器 Helper (GPU).app")
        let nearestOwner = ApplicationIconCache.shared.icon(for: browserHelper, version: nil).tiffRepresentation == own
        print(nearestOwner ? "PASS: deeply nested helper uses nearest owner" : "FAIL: deeply nested helper uses the wrong owner")
        let mainPreserved = ApplicationIconCache.shared.icon(for: parent, version: nil).tiffRepresentation == parentIcon
        print(mainPreserved ? "PASS: top-level app icon preserved" : "FAIL: top-level icon changed")
        let unrelated = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/application-icons/unrelated.app")
        let unchanged = ApplicationIconCache.shared.icon(for: unrelated, version: nil).tiffRepresentation == NSWorkspace.shared.icon(forFile: unrelated.path).tiffRepresentation
        print(unchanged ? "PASS: unrelated generic icon stays unchanged" : "FAIL: unrelated app assigned an owner")
        let staging = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/application-icons/fixtures/\(UUID().uuidString)/Owner.app.installing")
        let resources = staging.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data(contentsOf: parent.appendingPathComponent("Contents/Info.plist")).write(to: staging.appendingPathComponent("Contents/Info.plist"))
        try Data(contentsOf: parent.appendingPathComponent("Contents/Resources/icon.icns")).write(to: resources.appendingPathComponent("icon.icns"))
        for name in ["WorkBuddy Helper.app", "WorkBuddy Helper (GPU).app", "WorkBuddy Helper (Plugin).app", "WorkBuddy Helper (Renderer).app", "WorkBuddy Legacy Auto Launch Cleaner.app"] {
            let target = staging.appendingPathComponent("Contents/Frameworks/\(name)")
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: parent.appendingPathComponent("Contents/Frameworks/\(name)"), to: target)
        }
        guard let expectedStaging = Bundle(url: staging)?.image(forResource: NSImage.Name("icon.icns"))?.tiffRepresentation else {
            print("SKIP: nonstandard installed-bundle fixture unavailable")
            exit(77)
        }
        var stagingPassed = true
        for name in ["WorkBuddy Helper.app", "WorkBuddy Helper (GPU).app", "WorkBuddy Helper (Plugin).app", "WorkBuddy Helper (Renderer).app", "WorkBuddy Legacy Auto Launch Cleaner.app"] {
            let url = staging.appendingPathComponent("Contents/Frameworks/\(name)")
            let matches = ApplicationIconCache.shared.icon(for: url, version: nil).tiffRepresentation == expectedStaging
            print(matches ? "PASS: nonstandard owner / \(name)" : "FAIL: nonstandard owner / \(name)")
            stagingPassed = stagingPassed && matches
        }
        if !stagingPassed || !passed || !browserPreserved || !mainPreserved || !unchanged || !nearestOwner { exit(1) }
    }
}
