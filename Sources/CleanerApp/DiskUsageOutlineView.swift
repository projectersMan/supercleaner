import CleanerCore
import AppKit
import SwiftUI

struct DiskUsageOutlineView: View {
    @ObservedObject var model: AppModel
    let roots: [DiskUsageNode]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(model.sortedDiskNodes(roots)) { node in
                    DiskUsageTreeRow(model: model, node: node, depth: 0)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 8)
        }
        .accessibilityLabel(L10n.text("磁盘占用目录和大文件"))
    }
}

private struct DiskUsageTreeRow: View {
    @ObservedObject var model: AppModel
    let node: DiskUsageNode
    let depth: Int
    @State private var expansionOverride: Bool?
    @State private var isHovered = false

    private var isExpanded: Bool { expansionOverride ?? (depth == 0 && node.kind == .directory) }

    private var children: [DiskUsageNode] {
        if case let .loaded(children) = node.children {
            return children
        }
        return []
    }

    var body: some View {
        let candidate = model.diskFileCandidate(for: node)
        VStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if node.kind == .directory {
                        Button { expansionOverride = !isExpanded } label: {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right").frame(width: 14)
                        }
                        .buttonStyle(.plain)
                        .disabled(children.isEmpty)
                        .accessibilityLabel(isExpanded ? L10n.text("折叠 {0}", String(describing: node.url.lastPathComponent)) : L10n.text("展开 {0}", String(describing: node.url.lastPathComponent)))
                    } else {
                        Toggle(
                            isOn: Binding(get: { model.isDiskFileSelected(node) }, set: { _ in model.toggleDiskFile(node) })
                        ) { EmptyView() }
                        .toggleStyle(.checkbox).labelsHidden()
                        .disabled(!node.isReadable || candidate?.risk.isSelectable != true)
                        .accessibilityLabel(model.isDiskFileSelected(node) ? L10n.text("从计划移除 {0}", String(describing: node.url.lastPathComponent)) : L10n.text("将 {0} 加入计划", String(describing: node.url.lastPathComponent)))
                    }
                    Image(systemName: node.kind == .directory ? "folder.fill" : "doc.fill")
                        .foregroundColor(node.kind == .directory ? .accentColor : .secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.url.lastPathComponent).font(.headline).lineLimit(2)
                        if node.kind == .directory { Text(L10n.text("{0} 个直接子项", String(describing: node.childCount))).font(.caption).foregroundColor(.secondary) }
                    }
                    Spacer()
                    Text(ByteCountFormatter.cleanerString(bytes: node.recursiveBytes)).foregroundColor(.secondary)
                }
                Text(node.url.path)
                    .font(.caption.monospaced()).foregroundColor(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { metadata }
                    VStack(alignment: .leading, spacing: 6) { metadata }
                }
                .font(.caption).foregroundColor(.secondary)
                if node.kind == .directory {
                    Label(L10n.text("目录只用于展开和理解占用，不会作为一个整体加入清理计划。"), systemImage: "folder.badge.questionmark")
                        .font(.caption).foregroundColor(.secondary)
                } else if candidate?.risk.isSelectable != true || !node.isReadable {
                    Label(candidate?.evidence.last?.summary ?? L10n.text("无法验证文件，请刷新扫描"), systemImage: "lock.fill")
                        .font(.caption).foregroundColor(.secondary)
                } else if candidate?.requiresExplicitSelection == true {
                    Text(L10n.text("仅支持手动选择：请确认文件用途，删除可能影响相关应用或项目"))
                        .font(.caption).foregroundColor(.secondary)
                } else if let recommendation = candidate?.largeFileRecommendation {
                    let description = recommendation.details.map { L10n.text("{0} · 保留：{1}", recommendation.summary, $0) }
                    Text(description ?? recommendation.summary).font(.caption).foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(16)
            .padding(.leading, CGFloat(depth) * 18)
            .contentShape(Rectangle())
            .background((model.isDiskFileSelected(node) || isHovered) ? Color.accentColor.opacity(0.08) : Color.clear)
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.secondary.opacity(0.12)), alignment: .bottom)
            .onHover { isHovered = $0 }
            .onTapGesture { performRowAction(clickCount: 1) }
            .contextMenu {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([node.url.standardizedFileURL])
                } label: {
                    Label(L10n.text("在 Finder 中打开"), systemImage: "folder")
                }
            }
            .accessibilityAddTraits(model.selectedDiskNodeURL == node.url ? .isSelected : [])

            if isExpanded {
                ForEach(model.sortedDiskNodes(children)) { child in
                    DiskUsageTreeRow(model: model, node: child, depth: depth + 1)
                }
            }
        }
    }

    @ViewBuilder private var metadata: some View {
        Text(L10n.text("类型：{0}", String(describing: node.kind == .directory ? L10n.text("目录") : L10n.text("文件"))))
        Text(L10n.text("自身大小：{0}", String(describing: ByteCountFormatter.cleanerString(bytes: node.ownBytes))))
        Text(L10n.text("累计占用：{0}", String(describing: ByteCountFormatter.cleanerString(bytes: node.recursiveBytes))))
        Text(L10n.text("修改时间：{0}", String(describing: node.modifiedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.language.locale)))))
    }

    private func performRowAction(clickCount: Int) {
        model.focusDiskNode(node)
        if DirectoryRowInteraction.action(
            clickCount: clickCount,
            kind: node.kind,
            hasChildren: !children.isEmpty
        ) == .selectAndToggleExpansion {
            expansionOverride = !isExpanded
        }
    }
}
