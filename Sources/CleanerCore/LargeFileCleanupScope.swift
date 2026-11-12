import Foundation

/// Manual selection accepts user-owned paths; recommendations remain conservative.
/// PathPolicy and ProtectionPolicy independently enforce protected locations.
struct LargeFileCleanupScope {
    let homeDirectory: URL

    func allowsInstaller(_ url: URL) -> Bool {
        guard InstallerDiscovery.fileExtensions.contains(url.pathExtension.lowercased()), url.isFileURL else { return false }
        return allowsPath(url.standardizedFileURL, home: homeDirectory.standardizedFileURL, forManualSelection: false, installer: true)
            && allowsPath(url.resolvingSymlinksInPath().standardizedFileURL, home: homeDirectory.resolvingSymlinksInPath().standardizedFileURL, forManualSelection: false, installer: true)
    }

    func allows(_ url: URL, forManualSelection: Bool = false) -> Bool {
        guard url.isFileURL else { return false }
        let home = homeDirectory.resolvingSymlinksInPath().standardizedFileURL
        let literal = url.standardizedFileURL
        let physical = literal.resolvingSymlinksInPath().standardizedFileURL
        return allowsPath(literal, home: homeDirectory.standardizedFileURL, forManualSelection: forManualSelection)
            && allowsPath(physical, home: home, forManualSelection: forManualSelection)
    }

    private func allowsPath(_ url: URL, home: URL, forManualSelection: Bool, installer: Bool = false) -> Bool {
        guard url.path.hasPrefix(home.path + "/") else { return false }
        if forManualSelection { return true }
        let components = Array(url.pathComponents.dropFirst(home.pathComponents.count))
        let roots: Set<String> = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"]
        guard !components.isEmpty else { return false }
        guard installer || (components.count >= 2 && components.first.map(roots.contains) == true) else { return false }
        let protected: Set<String> = [
            "library", "applications", "miniconda3", "miniconda", "anaconda3", "anaconda",
            "miniforge3", "mambaforge", "venv", "env", "envs", "site-packages", "dist-packages",
            "node_modules", "bower_components", "vendor", "sdk", "sdks", "toolchains",
            "bin", "sbin", "lib", "lib64", "include",
        ]
        let packages: Set<String> = ["app", "framework", "bundle", "plugin", "xcodeproj", "xcworkspace", "photoslibrary", "photolibrary"]
        for component in components {
            if component.hasPrefix(".") || protected.contains(component.lowercased())
                || packages.contains((component as NSString).pathExtension.lowercased()) { return false }
        }
        if ["dylib", "so", "dll", "exe", "a", "o", "pyc"].contains(url.pathExtension.lowercased()) { return false }
        if FileManager.default.isExecutableFile(atPath: url.path),
           (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true { return false }
        var ancestor = url.deletingLastPathComponent()
        while ancestor.path != home.path {
            if (try? ancestor.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true { return false }
            // Environment and project names are arbitrary: inspect their markers as well.
            let markers = ["pyvenv.cfg", "conda-meta", ".git", "package.json", "pyproject.toml", "Cargo.toml", "Package.swift"]
            if !installer && markers.contains(where: {
                FileManager.default.fileExists(atPath: ancestor.appendingPathComponent($0).path)
            }) { return false }
            ancestor.deleteLastPathComponent()
        }
        return true
    }
}
