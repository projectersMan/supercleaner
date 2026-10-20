import Foundation

public enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public static let preferenceKey = "appLanguage"
    public var id: String { rawValue }
    public var nativeName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "中文（简体）"
        }
    }
    public var locale: Locale { Locale(identifier: rawValue) }

    /// An absent or unsupported preference always means English, regardless of the OS language.
    public static func selected(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .english
    }
}

public enum L10n {
    /// Keep one language for the entire process, including background scans and their evidence.
    /// A settings change applies at next launch, without interrupting active operations.
    public static let language = AppLanguage.selected()

    public static func text(_ source: String, _ arguments: String...) -> String {
        text(source, language: language, arguments: arguments)
    }

    public static func text(_ source: String, language: AppLanguage, arguments: [String] = []) -> String {
        let bundle = bundles[language] ?? resourceBundle
        let template = bundle.localizedString(forKey: source, value: source, table: nil)
        guard !arguments.isEmpty else { return template }
        let result = NSMutableString(string: template)
        // Replace original placeholder ranges once. Argument text (paths, names, errors) is
        // never treated as a template or translated, even if it contains "{0}" or percent signs.
        let range = NSRange(location: 0, length: (template as NSString).length)
        for match in placeholders.matches(in: template, range: range).reversed() {
            let number = (template as NSString).substring(with: match.range(at: 1))
            if let index = Int(number), arguments.indices.contains(index) {
                result.replaceCharacters(in: match.range, with: arguments[index])
            }
        }
        return result as String
    }

    private static let placeholders = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)
    private static let resourceBundle: Bundle = {
        // SwiftPM's generated accessor also contains an absolute build-directory fallback.
        // Prefer the installed resources for the GUI, embedded CLI, and nested Helper.
        if let app = ReleaseConfiguration.applicationBundle(),
           let url = app.url(forResource: "SuperCleaner_CleanerCore", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
    private static let bundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues:
        AppLanguage.allCases.compactMap { language in
            // SwiftPM normalizes localization directory names to lowercase.
            guard let name = resourceBundle.localizations.first(where: {
                $0.caseInsensitiveCompare(language.rawValue) == .orderedSame
            }),
                  let url = resourceBundle.url(forResource: name, withExtension: "lproj"),
                  let bundle = Bundle(url: url) else { return nil }
            return (language, bundle)
        }
    )
}
