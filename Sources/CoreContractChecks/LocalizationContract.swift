import CleanerCore
import Foundation

func runLocalizationContracts() throws {
    let processLanguage = L10n.language
    if let index = CommandLine.arguments.firstIndex(of: "-appLanguage"),
       CommandLine.arguments.indices.contains(index + 1) {
        require(processLanguage.rawValue == CommandLine.arguments[index + 1], "process uses requested test language")
    }
    let domain = "SuperCleaner.LanguageTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
    defer { defaults.removePersistentDomain(forName: domain) }
    require(AppLanguage.selected(in: defaults) == .english, "fresh preferences default to English")
    defaults.set("unsupported", forKey: AppLanguage.preferenceKey)
    require(AppLanguage.selected(in: defaults) == .english, "unknown preferences fall back to English")
    defaults.set("zh-Hans", forKey: AppLanguage.preferenceKey)
    let reopened = UserDefaults(suiteName: domain)!
    reopened.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
    require(AppLanguage.selected(in: reopened) == .simplifiedChinese, "Chinese selection persists across preference instances")
    defaults.set("en", forKey: AppLanguage.preferenceKey)
    require(AppLanguage.selected(in: defaults) == .english, "can switch back to English")
    require(L10n.text("设置", language: .english) == "Settings", "English catalog is packaged")
    require(L10n.text("设置", language: .simplifiedChinese) == "设置", "Chinese catalog is packaged")
    require(L10n.text("应用版本", language: .english) == "App version", "version settings are localized")
    let path = "/tmp/中文 {1} 100% \"file\""
    require(L10n.text("将 {0} 加入{1}", language: .english, arguments: [path, "plan"]) == "Add \(path) to plan", "arguments are preserved verbatim and not recursively formatted")
    require(L10n.text("从{0}移除 {1}", language: .english, arguments: ["plan", "Cache"]) == "Remove Cache from plan", "translation can reorder arguments")
    require(L10n.text("third-party evidence", language: .english) == "third-party evidence", "unknown content is preserved")

    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let app = root.appendingPathComponent("VersionFixture.app")
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let info: [String: Any] = [
        "CFBundleIdentifier": "com.example.VersionFixture",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "2.3.4",
        "CFBundleVersion": "987",
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
    let version = AppVersion(bundle: Bundle(url: app)!)
    require(version.version == "2.3.4" && version.build == "987", "version display uses installed metadata rather than source defaults")
    require(L10n.language == processLanguage, "preference changes do not change an in-flight process language")
    print("PASS: language defaults, persistence, catalogs, interpolation, and bundle version (\(processLanguage.rawValue))")
}
