import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Launch Services resolves the icon declared by the installed application bundle,
/// including icons in asset catalogs. Generic nested helpers inherit their owner icon.
/// Cache it so list redraws do not read it again.
@MainActor final class ApplicationIconCache {
    static let shared = ApplicationIconCache()
    private let images = NSCache<NSString, NSImage>()
    private lazy var genericApplicationIconData = NSWorkspace.shared.icon(for: .applicationBundle).tiffRepresentation

    private init() { images.countLimit = 256 }

    func icon(for bundleURL: URL, version: String?) -> NSImage {
        let key = (bundleURL.standardizedFileURL.path + "|" + (version ?? "")) as NSString
        if let image = images.object(forKey: key) { return image }
        var image = NSWorkspace.shared.icon(forFile: bundleURL.path)
        let path = bundleURL.standardizedFileURL.path
        var ancestor = bundleURL.standardizedFileURL.deletingLastPathComponent()
        while !ancestor.path.isEmpty && ancestor.path != "/" {
            if path.hasPrefix(ancestor.appendingPathComponent("Contents").path + "/"),
               let owner = Bundle(url: ancestor),
               owner.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL" {
                guard let generic = genericApplicationIconData, image.tiffRepresentation == generic else { break }
                if ancestor.pathExtension.lowercased() == "app" {
                    image = NSWorkspace.shared.icon(forFile: ancestor.path)
                } else if let declared = declaredIcon(in: owner) {
                    image = declared
                }
            }
            ancestor.deleteLastPathComponent()
        }
        images.setObject(image, forKey: key)
        return image
    }

    private func declaredIcon(in bundle: Bundle) -> NSImage? {
        for key in ["CFBundleIconName", "CFBundleIconFile"] {
            if let name = bundle.object(forInfoDictionaryKey: key) as? String,
               let image = bundle.image(forResource: NSImage.Name(name)) {
                return image
            }
        }
        return nil
    }
}

struct ApplicationIconView: View {
    let bundleURL: URL
    let version: String?
    var body: some View {
        Image(nsImage: ApplicationIconCache.shared.icon(for: bundleURL, version: version))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }
}
