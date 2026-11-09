import AppKit
import CleanerCore
import SwiftUI

struct DiskSpaceView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !model.hasScanResult(for: .largeFiles) {
                if model.isCurrentModuleScanning, let message = model.scanProgressByModule[.largeFiles]?.message {
                    EmptyState(title: L10n.text("扫描中"), message: message, icon: "doc.on.doc")
                } else {
                    ScanRequiredView(destinationTitle: L10n.text("重复大文件")) { model.navigateToScan() }
                }
            } else if let tree = model.diskUsageTree {
                if model.largeFileThresholdNeedsRefresh {
                    HStack {
                        Label(L10n.text("大文件标准已改为 ≥ {0}，刷新后应用", String(describing: model.largeFileThreshold.shortTitle)), systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                            .foregroundColor(.orange)
                        Spacer()
                        Button(L10n.text("应用并刷新")) { model.refreshModule(.largeFiles) }
                            .disabled(model.isScanRunning)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10).background(.orange.opacity(0.08))
                    Divider()
                }
                LargeFileFilterBar(model: model, tree: tree, searchText: $searchText)
                Divider()
                if model.scanProgressByModule[.largeFiles]?.limitations.contains(where: { $0.reason == .budget }) == true {
                    Label(L10n.text("查重未覆盖全部候选，仅推荐已核验的重复项"), systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 8)
                }
                if model.showsDuplicateLargeFilesOnly {
                    duplicateList
                } else if tree.roots.isEmpty {
                    EmptyState(title: L10n.text("未发现符合条件的大文件"), message: L10n.text("本次扫描未发现达到当前大小标准的文件。"), icon: "doc.text.magnifyingglass")
                } else {
                    VStack(spacing: 0) {
                        diskSummary(tree)
                        DiskUsageOutlineView(model: model, roots: filteredRoots(tree.roots))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func diskSummary(_ tree: DiskUsageTree) -> some View {
        HStack(spacing: 12) {
            Label(tree.analysisState == .complete ? L10n.text("目录分析完成") : L10n.text("系统索引结果"),
                systemImage: tree.analysisState == .complete ? "folder" : "bolt")
            Text(L10n.text("{0} 个 ≥ {1} 文件", String(tree.largeFiles.count), ByteCountFormatter.cleanerString(bytes: tree.minimumFileBytes)))
            Spacer()
            Text(ByteCountFormatter.cleanerString(bytes: tree.roots.reduce(0) { $0 + $1.recursiveBytes })).fontWeight(.semibold)
        }
        .font(.caption).foregroundColor(.secondary)
        .padding(.horizontal, 18).padding(.vertical, 8)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("重复大文件")).font(.largeTitle.bold())
                Text(L10n.text("扫描会识别安装包、核验相同副本和已完整解压的 ZIP，并勾选建议清理的文件供你确认。"))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(24)
    }

    private var visibleDuplicates: [CleanupCandidate] {
        let query = model.reviewQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.duplicateLargeFiles.filter { query.isEmpty || $0.url.path.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                if model.largeFileSortOrder == .selection {
                    let selectedLeft = model.selectedIDs.contains(lhs.id)
                    let selectedRight = model.selectedIDs.contains(rhs.id)
                    if selectedLeft != selectedRight { return selectedLeft }
                }
                if model.largeFileSortOrder == .directory {
                    let left = lhs.url.deletingLastPathComponent().path
                    let right = rhs.url.deletingLastPathComponent().path
                    if left != right { return left.localizedStandardCompare(right) == .orderedAscending }
                }
                if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
                return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
            }
    }

    @ViewBuilder private var duplicateList: some View {
        let candidates = visibleDuplicates
        if candidates.isEmpty {
            EmptyState(title: L10n.text("没有匹配的重复大文件"),
                message: L10n.text("可切换到全部大文件查看扫描清单。"), icon: "doc.on.doc")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(candidates) { candidate in
                        DuplicateLargeFileRow(model: model, candidate: candidate)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 8)
            }
        }
    }

    private func filteredRoots(_ roots: [DiskUsageNode]) -> [DiskUsageNode] {
        let query = model.reviewQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return roots }
        func filtered(_ node: DiskUsageNode) -> DiskUsageNode? {
            let matches = node.url.path.localizedCaseInsensitiveContains(query)
            guard case let .loaded(children) = node.children else { return matches ? node : nil }
            let filteredChildren = children.compactMap(filtered)
            guard matches || !filteredChildren.isEmpty else { return nil }
            return DiskUsageNode(
                url: node.url,
                kind: node.kind,
                ownBytes: node.ownBytes,
                recursiveBytes: node.recursiveBytes,
                childCount: node.childCount,
                modifiedAt: node.modifiedAt,
                isReadable: node.isReadable,
                children: .loaded(filteredChildren),
                identity: node.identity
            )
        }
        return roots.compactMap(filtered)
    }
}

private struct LargeFileFilterBar: View {
    @ObservedObject var model: AppModel
    let tree: DiskUsageTree
    @Binding var searchText: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                search
                scope
                sort
                count
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) { search; Spacer(minLength: 0); count }
                HStack(spacing: 12) { scope; sort; Spacer(minLength: 0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.caption)
        .padding(.horizontal, 18).padding(.vertical, 10).background(.bar)
    }

    private var search: some View {
        TextField(L10n.text("搜索文件名或完整路径"), text: $searchText)
            .textFieldStyle(.roundedBorder).frame(width: 260)
            .onAppear { searchText = model.reviewQuery }
            .onChange(of: searchText) { value in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    guard searchText == value else { return }
                    model.reviewQuery = value
                }
            }
    }

    private var scope: some View {
        ScopePicker(labels: [L10n.text("重复大文件"), L10n.text("全部大文件")], selection: Binding(
            get: { model.showsDuplicateLargeFilesOnly ? 0 : 1 },
            set: { model.showsDuplicateLargeFilesOnly = $0 == 0 }
        ))
        .frame(width: 420).fixedSize(horizontal: false, vertical: true)
    }

    private var sort: some View {
        Picker(L10n.text("排序"), selection: $model.largeFileSortOrder) {
            ForEach(LargeFileSortOrder.allCases, id: \.self) { order in
                Text(order.displayTitle).tag(order)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 140).fixedSize(horizontal: false, vertical: true)
    }

    private var count: some View {
        let count = model.showsDuplicateLargeFilesOnly ? model.duplicateLargeFiles.count : tree.largeFiles.count
        return Text(L10n.text("{0} 个文件", String(count)))
            .monospacedDigit().foregroundColor(.secondary)
            .frame(width: 140, alignment: .trailing).lineLimit(1)
    }
}

private struct DuplicateLargeFileRow: View {
    @ObservedObject var model: AppModel
    let candidate: CleanupCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(candidate.displayName, isOn: Binding(
                get: { model.selectedIDs.contains(candidate.id) },
                set: { _ in model.toggle(candidate) }
            ))
            .toggleStyle(.checkbox).labelsHidden()
            Image(systemName: candidate.largeFileProof?.reason == .extractedZIP ? "archivebox" : "doc.on.doc")
                .foregroundColor(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.displayName).font(.headline)
                Text(candidate.url.path).font(.caption.monospaced()).textSelection(.enabled)
                if let proof = candidate.largeFileProof, let retained = proof.retained.first {
                    Text(L10n.text("{0} · 保留：{1}", proof.title, retained.url.path))
                        .font(.caption).textSelection(.enabled)
                }
            }
            Spacer()
            Text(ByteCountFormatter.cleanerString(bytes: candidate.bytes)).monospacedDigit()
        }
        .foregroundColor(.secondary)
        .padding(14)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.secondary.opacity(0.12)), alignment: .bottom)
        .contextMenu {
            Button(L10n.text("在 Finder 中打开")) { NSWorkspace.shared.activateFileViewerSelecting([candidate.url]) }
        }
    }
}
