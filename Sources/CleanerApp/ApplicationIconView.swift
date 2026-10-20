import AppKit
import SwiftUI

/// Launch Services resolves the icon declared by the installed application bundle,
/// including icons in asset catalogs. Cache it so list redraws do not read it again.
@MainActor private final class ApplicationIconCache {
    static let shared = ApplicationIconCache()
    private let images = NSCache<NSString, NSImage>()

    private init() { images.countLimit = 256 }

    func icon(for bundleURL: URL, version: String?) -> NSImage {
        let key = (bundleURL.standardizedFileURL.path + "|" + (version ?? "")) as NSString
        if let image = images.object(forKey: key) { return image }
        let image = NSWorkspace.shared.icon(forFile: bundleURL.path)
        images.setObject(image, forKey: key)
        return image
    }
}

struct ApplicationIconView: View {
    let bundleURL: URL
    let version: String?
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "app")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
        .task(id: bundleURL.path + "|" + (version ?? "")) {
            icon = ApplicationIconCache.shared.icon(for: bundleURL, version: version)
        }
    }
}
