import AppKit
import Foundation

@main enum IconFirstEntry {
    @MainActor static func main() throws {
        let apps = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let visible = Array(apps.prefix(16))
        let start = Date()
        for url in visible { _ = ApplicationIconCache.shared.icon(for: url, version: nil) }
        let cold = Date().timeIntervalSince(start)
        let warmStart = Date()
        for url in visible { _ = ApplicationIconCache.shared.icon(for: url, version: nil) }
        let warm = Date().timeIntervalSince(warmStart)
        print("Icon first screen: \(visible.count) installed apps; cold \(cold)s; warm \(warm)s")
    }
}
