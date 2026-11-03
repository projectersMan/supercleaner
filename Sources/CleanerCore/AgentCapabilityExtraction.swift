import CryptoKit
import Foundation

public struct AgentOverlapPolicy: Codable, Sendable {
    public let algorithmVersion: String
    public let minimumFeatureSimilarity: Float
    public let minimumFeatureLetters: Int
    public let maximumFeatureCharacters: Int

    public var fingerprint: String {
        let values = [algorithmVersion, String(minimumFeatureSimilarity), String(minimumFeatureLetters),
                      String(maximumFeatureCharacters)]
        return SHA256.hash(data: Data(values.joined(separator: "|").utf8)).map(Self.hexByte).joined()
    }

    public static func load() throws -> Self {
        guard let url = Bundle.module.url(forResource: "agent-overlap-policy", withExtension: "json") else {
            throw AgentOverlapError.missingAnalysisPolicy
        }
        let policy = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard !policy.algorithmVersion.isEmpty,
              (0.5...1).contains(policy.minimumFeatureSimilarity),
              policy.minimumFeatureLetters > 0,
              policy.maximumFeatureCharacters >= policy.minimumFeatureLetters else {
            throw AgentOverlapError.invalidAnalysisPolicy
        }
        return policy
    }

    private static func hexByte(_ value: UInt8) -> String { String(format: "%02x", value) }
}

/// Extracts evidence from the scan snapshot; it never opens a manifest again.
public enum AgentCapabilityExtraction {
    public static func candidates(for input: AgentOverlapInput, policy: AgentOverlapPolicy) -> [String] {
        if input.kind == .mcp {
            var descriptions = [String]()
            var seen = Set<String>()
            for feature in input.features {
                let text = feature.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count <= policy.maximumFeatureCharacters {
                    if !text.isEmpty, seen.insert(normalized(text)).inserted { descriptions.append(text) }
                } else {
                    append(text, policy: policy, result: &descriptions, seen: &seen)
                }
            }
            return descriptions
        }
        var result = [String]()
        var seen = Set<String>()
        append(input.description, policy: policy, result: &result, seen: &seen)
        var isFenced = false
        var referenceDepth: Int?
        var paragraph = [String]()
        let texts = input.features
        for text in texts {
            for rawLine in text.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("```") || line.hasPrefix("~~~") {
                    flush(&paragraph, policy: policy, result: &result, seen: &seen)
                    isFenced.toggle()
                    continue
                }
                guard !isFenced else { continue }
                if line.hasPrefix("#") {
                    flush(&paragraph, policy: policy, result: &result, seen: &seen)
                    let depth = line.prefix(while: { $0 == "#" }).count
                    if let previous = referenceDepth, depth <= previous { referenceDepth = nil }
                    let heading = normalized(String(line.dropFirst(depth)))
                    if ["reference", "references", "references and examples", "参考", "参考资料", "参考文档", "links", "相关链接"].contains(heading) {
                        referenceDepth = depth
                    }
                    continue
                }
                guard referenceDepth == nil else { continue }
                if line.isEmpty || line.hasPrefix("<!--") {
                    flush(&paragraph, policy: policy, result: &result, seen: &seen)
                    continue
                }
                if line.hasPrefix("|") {
                    flush(&paragraph, policy: policy, result: &result, seen: &seen)
                    if line.range(of: "^[| :\\-]+$", options: .regularExpression) == nil {
                        append(line.replacingOccurrences(of: "|", with: " "), policy: policy, result: &result, seen: &seen)
                    }
                    continue
                }
                let isList = line.range(of: "^([-*+] |[0-9]+[.)] )", options: .regularExpression) != nil
                if isList {
                    flush(&paragraph, policy: policy, result: &result, seen: &seen)
                    append(line, policy: policy, result: &result, seen: &seen)
                } else {
                    paragraph.append(line)
                }
            }
            flush(&paragraph, policy: policy, result: &result, seen: &seen)
        }
        return result
    }

    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func flush(_ paragraph: inout [String], policy: AgentOverlapPolicy, result: inout [String], seen: inout Set<String>) {
        append(paragraph.joined(separator: " "), policy: policy, result: &result, seen: &seen)
        paragraph.removeAll(keepingCapacity: true)
    }

    private static func append(_ text: String, policy: AgentOverlapPolicy, result: inout [String], seen: inout Set<String>) {
        let cleaned = text
            .replacingOccurrences(of: "^([-*+] |[0-9]+[.)] )", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[*`]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.unicodeScalars.filter(CharacterSet.letters.contains).count >= policy.minimumFeatureLetters else { return }
        // Split oversized descriptions; retain every part rather than sampling capabilities.
        let pieces = cleaned.count <= policy.maximumFeatureCharacters
            ? [cleaned]
            : cleaned.components(separatedBy: CharacterSet(charactersIn: ".。;；!?！？"))
        for piece in pieces {
            let candidate = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            var remaining = candidate[...]
            while !remaining.isEmpty {
                let fragment = String(remaining.prefix(policy.maximumFeatureCharacters))
                remaining = remaining.dropFirst(fragment.count)
                guard fragment.unicodeScalars.filter(CharacterSet.letters.contains).count >= policy.minimumFeatureLetters else { continue }
                if seen.insert(normalized(fragment)).inserted { result.append(fragment) }
            }
        }
    }
}
