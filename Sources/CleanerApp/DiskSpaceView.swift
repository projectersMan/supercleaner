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
                ScanRequiredView(destinationTitle: "大文件") { model.navigateToScan() }
            } else if let tree = model.diskUsageTree {
                if model.largeFileThresholdNeedsRefresh {
                    HStack {
                        Label("大文件标准已改为 ≥ \(model.largeFileThreshold.shortTitle)，刷新后应用", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                            .foregroundColor(.orange)
                        Spacer()
                        Button("应用并刷新") { model.refreshModule(.largeFiles) }
                            .disabled(model.phase == .scanning)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10).background(.orange.opacity(0.08))
                    Divider()
                }
                LargeFileFilterBar(model: model, tree: tree, searchText: $searchText)
                Divider()
                if tree.roots.isEmpty {
                    EmptyState(title: "未发现符合条件的大文件", message: "本次扫描未发现达到当前大小标准的文件。", icon: "doc.text.magnifyingglass")
                } else {
                    DiskUsageOutlineView(model: model, roots: filteredRoots(tree.roots))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("大文件").font(.largeTitle.bold())
                Text("目录用于理解空间来源；只有具体文件可以勾选，删除前会自动检查。")
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(24)
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
        HStack(spacing: 12) {
            TextField("搜索文件名或完整路径", text: $searchText)
                .textFieldStyle(.roundedBorder).frame(minWidth: 180)
                .onAppear { searchText = model.reviewQuery }
                .onChange(of: searchText) { value in
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(180))
                        guard searchText == value else { return }
                        model.reviewQuery = value
                    }
                }
            Picker("排序", selection: $model.largeFileSortOrder) {
                ForEach(LargeFileSortOrder.allCases, id: \.self) { order in
                    Text(order.displayTitle).tag(order)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            Spacer()
            Label(tree.analysisState == .complete ? "目录分析完成" : "系统索引结果", systemImage: tree.analysisState == .complete ? "folder" : "bolt")
            Label("\(tree.largeFiles.count) 个 ≥ \(ByteCountFormatter.cleanerString(bytes: tree.minimumFileBytes)) 文件", systemImage: "doc")
            Text(ByteCountFormatter.cleanerString(bytes: tree.roots.reduce(0) { $0 + $1.recursiveBytes }))
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 18).padding(.vertical, 10).background(.bar)
    }
}
