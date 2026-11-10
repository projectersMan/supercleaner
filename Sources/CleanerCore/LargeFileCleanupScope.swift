import Foundation

/// Large-file cleanup is limited to personal content, never installed runtime components.
struct LargeFileCleanupScope {
    let homeDirectory: URL

    func allows(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let home = homeDirectory.resolvingSymlinksInPath().standardizedFileURL
        let literal = url.standardizedFileURL
        let physical = literal.resolvingSymlinksInPath().standardizedFileURL
        return allowsPath(literal, home: homeDirectory.standardizedFileURL)
            && allowsPath(physical, home: home)
    }

    private func allowsPath(_ url: URL, home: URL) -> Bool {
        guard url.path.hasPrefix(home.path + "/") else { return false }
        let components = Array(url.pathComponents.dropFirst(home.pathComponents.count))
        let roots: Set<String> = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"]
        guard components.count >= 2, let root = components.first, roots.contains(root) else { return false }
        let protected: Set<String> = [
            "library", "applications", "miniconda3", "miniconda", "anaconda3", "anaconda",
            "miniforge3", "mambaforge", "venv", "env", "envs", "site-packages", "dist-packages",
            "node_modules", "bower_components", "vendor", "sdk", "sdks", "toolchains",
            "bin", "sbin", "lib", "lib64", "include",
        ]
        let packages: Set<String> = ["app", "framework", "bundle", "plugin", "xcodeproj", "xcworkspace", "photoslibrary", "photolibrary"]
        for component in components.dropFirst() {
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
            if ["pyvenv.cfg", "conda-meta", ".git", "package.json", "pyproject.toml", "Cargo.toml", "Package.swift"].contains(where: {
                FileManager.default.fileExists(atPath: ancestor.appendingPathComponent($0).path)
            }) { return false }
            ancestor.deleteLastPathComponent()
        }
        return true
    }
}
