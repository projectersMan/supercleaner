import CryptoKit
import Darwin
import Foundation

struct LargeFileContentAnalysis {
    let candidates: [CleanupCandidate]
    let limited: Bool
}

struct LargeFileContentBudget {
    private let clock = ContinuousClock()
    private let deadline: ContinuousClock.Instant
    private var bytes: UInt64
    private var entries: Int
    private(set) var limited = false

    init(bytes: UInt64, entries: Int, time: Duration) {
        self.bytes = bytes
        self.entries = entries
        deadline = clock.now.advanced(by: time)
    }

    mutating func take(bytes: UInt64, entries: Int) -> Bool {
        guard !Task.isCancelled else { return false }
        guard !limited, clock.now < deadline, bytes <= self.bytes, entries <= self.entries else {
            limited = true
            return false
        }
        self.bytes -= bytes
        self.entries -= entries
        return true
    }
}

struct LargeFileContentAnalyzer {
    let context: ScanContext
    let minimumBytes: UInt64
    let preselectInstallers: Bool

    func analyze(_ candidates: [CleanupCandidate]) -> LargeFileContentAnalysis {
        LargeFileContentIO.withLocalAccess { analyzeLocal(candidates) }
            ?? LargeFileContentAnalysis(candidates: candidates, limited: true)
    }

    private func analyzeLocal(_ candidates: [CleanupCandidate]) -> LargeFileContentAnalysis {
        // Separate limits keep either stage from exhausting the other's allowance.
        var copyBudget = LargeFileContentBudget(bytes: 64 << 30, entries: 50_000, time: .seconds(20))
        let eligible = candidates.filter { $0.risk.isSelectable && !$0.isActive && $0.requiresExplicitSelection != true }
        let groups = identicalGroups(eligible, budget: &copyBudget)
        var groupByPath: [String: Int] = [:]
        for (index, group) in groups.enumerated() {
            for item in group { groupByPath[item.url.path] = index }
        }

        var zipBudget = LargeFileContentBudget(bytes: 64 << 30, entries: 50_000, time: .seconds(20))
        var skippedZIPBudget = false
        var recommendations: [String: LargeFileCleanupProof] = [:]
        var targets = Set<String>()
        var keepers = Set<String>()
        var representedGroups = Set<Int>()

        for candidate in eligible.sorted(by: Self.pathOrder) where candidate.url.pathExtension.lowercased() == "zip" {
            guard zipBudget.take(bytes: 0, entries: 1) else { break }
            let group = groupByPath[candidate.url.path]
            if let group, representedGroups.contains(group) { continue }
            guard !keepers.contains(candidate.url.path), let snapshot = snapshot(candidate),
                  let result = ExtractedZIPAnalyzer(context: context, minimumBytes: minimumBytes)
                    .match(snapshot, avoiding: targets, budget: &zipBudget, skippedBudget: &skippedZIPBudget) else { continue }
            recommendations[snapshot.url.path] = .init(reason: .extractedZIP, target: snapshot, retained: result)
            targets.insert(snapshot.url.path)
            keepers.formUnion(result.map { $0.url.path })
            if let group { representedGroups.insert(group) }
        }

        for (index, group) in groups.enumerated() where !representedGroups.contains(index) {
            guard let keeper = group.first(where: { keepers.contains($0.url.path) }) ?? group.first,
                  let copy = group.first(where: { $0 != keeper && !keepers.contains($0.url.path) }) else { continue }
            recommendations[copy.url.path] = .init(reason: .identicalCopy, target: copy, retained: [keeper])
            targets.insert(copy.url.path)
        }

        return LargeFileContentAnalysis(candidates: candidates.map { candidate in
            let path = candidate.url.path
            if let proof = recommendations[path], proof.isCurrent(for: candidate) {
                return candidate.withLargeFileProof(proof)
            }
            let format = candidate.url.pathExtension.lowercased()
            // Keep one recommendation per verified group, and leave all retained ZIP members intact.
            guard !Task.isCancelled, InstallerDiscovery.fileExtensions.contains(format),
                  groupByPath[path] == nil, !keepers.contains(path),
                  candidate.risk.isSelectable, !candidate.isActive, candidate.requiresExplicitSelection != true,
                  snapshot(candidate, installer: true) != nil else { return candidate }
            return candidate.withLargeFileInstaller(format, preselected: preselectInstallers)
        }, limited: copyBudget.limited || zipBudget.limited || skippedZIPBudget)
    }

    private func identicalGroups(_ candidates: [CleanupCandidate], budget: inout LargeFileContentBudget) -> [[LargeFileContentSnapshot]] {
        let buckets = Dictionary(grouping: candidates, by: \.bytes)
        var output: [[LargeFileContentSnapshot]] = []
        for size in buckets.keys.sorted(by: >) {
            guard budget.take(bytes: 0, entries: 0), let bucket = buckets[size], bucket.count > 1 else {
                if budget.limited || Task.isCancelled { break }
                continue
            }
            var byHash: [SHA256.Digest: [[LargeFileContentSnapshot]]] = [:]
            for candidate in bucket.sorted(by: Self.pathOrder) {
                guard budget.take(bytes: 0, entries: 1) else { break }
                guard let file = snapshot(candidate), let digest = hash(file, budget: &budget) else { continue }
                var groups = byHash[digest] ?? []
                if let index = groups.firstIndex(where: { group in
                    guard let representative = group.first, !file.isSameObject(as: representative) else { return false }
                    return equal(file, representative, budget: &budget)
                }) {
                    groups[index].append(file)
                } else {
                    groups.append([file])
                }
                byHash[digest] = groups
            }
            output.append(contentsOf: byHash.values.flatMap { $0 }.filter { $0.count > 1 })
        }
        return output
    }

    private func snapshot(_ candidate: CleanupCandidate, installer: Bool = false) -> LargeFileContentSnapshot? {
        guard let file = Self.eligibleSnapshot(candidate.url, context: context, installer: installer), !file.isDirectory,
              file.bytes == candidate.bytes, file.device == candidate.identity.device,
              file.inode == candidate.identity.inode, file.modifiedSeconds == candidate.identity.modificationTime else { return nil }
        return file
    }

    static func eligibleSnapshot(_ url: URL, context: ScanContext, installer: Bool = false) -> LargeFileContentSnapshot? {
        let excluded = ["Library/CloudStorage", "Library/Mobile Documents"]
        let home = context.homeDirectory.resolvingSymlinksInPath().standardizedFileURL
        let literal = url.standardizedFileURL
        let path = literal.path
        let scope = LargeFileCleanupScope(homeDirectory: context.homeDirectory)
        guard (installer ? scope.allowsInstaller(url) : scope.allows(url)),
              path.hasPrefix(home.path + "/"),
              !excluded.contains(where: { path.hasPrefix(home.appendingPathComponent($0).path + "/") }),
              !DeletedContentScanExclusion(homeDirectory: home).contains(literal), !context.isActive(literal),
              (try? context.pathPolicy.validateCandidate(literal)) != nil,
              (try? context.protectionPolicy.validate(literal)) != nil,
              let snapshot = LargeFileContentSnapshot.at(literal), access(path, R_OK) == 0,
              !containsPackage(snapshot.isDirectory ? literal : literal.deletingLastPathComponent(), home: home) else { return nil }
        return snapshot
    }

    private static func containsPackage(_ url: URL, home: URL) -> Bool {
        var current = url
        while current.path != home.path {
            if (try? current.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true { return true }
            current.deleteLastPathComponent()
        }
        return false
    }

    private static func pathOrder(_ a: CleanupCandidate, _ b: CleanupCandidate) -> Bool { a.url.path < b.url.path }

    private func hash(_ file: LargeFileContentSnapshot, budget: inout LargeFileContentBudget) -> SHA256.Digest? {
        guard let fd = LargeFileContentIO.openFile(file) else { return nil }
        defer { close(fd) }
        var hasher = SHA256()
        var remaining = file.bytes
        while remaining > 0 {
            let count = min(remaining, UInt64(LargeFileContentIO.chunkBytes))
            guard budget.take(bytes: count, entries: 0),
                  let data = LargeFileContentIO.readChunk(fd, count: Int(count)), data.count == count else { return nil }
            hasher.update(data: data)
            remaining -= count
        }
        guard LargeFileContentIO.matches(fd, file), file.isCurrent else { return nil }
        return hasher.finalize()
    }

    private func equal(_ a: LargeFileContentSnapshot, _ b: LargeFileContentSnapshot, budget: inout LargeFileContentBudget) -> Bool {
        guard a.bytes == b.bytes, let first = LargeFileContentIO.openFile(a) else { return false }
        defer { close(first) }
        guard let second = LargeFileContentIO.openFile(b) else { return false }
        defer { close(second) }
        guard let attributes = LargeFileContentIO.attributes(first), attributes == LargeFileContentIO.attributes(second) else { return false }
        var remaining = a.bytes
        while remaining > 0 {
            let count = min(remaining, UInt64(LargeFileContentIO.chunkBytes))
            guard budget.take(bytes: count * 2, entries: 0),
                  let lhs = LargeFileContentIO.readChunk(first, count: Int(count)), lhs.count == count,
                  lhs == LargeFileContentIO.readChunk(second, count: Int(count)) else { return false }
            remaining -= count
        }
        return LargeFileContentIO.matches(first, a) && LargeFileContentIO.matches(second, b) && a.isCurrent && b.isCurrent
    }
}
