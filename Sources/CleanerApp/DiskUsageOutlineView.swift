import CleanerCore
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
    @State private var isExpanded = false

    private var children: [DiskUsageNode] {
        if case let .loaded(children) = node.children {
            return model.sortedDiskNodes(children)
        }
        return []
    }

    var body: some View {
        VStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if node.kind == .directory {
                        Button { isExpanded.toggle() } label: {
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
                        .disabled(!node.isReadable)
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
                }
            }
            .padding(16)
            .padding(.leading, CGFloat(depth) * 18)
            .contentShape(Rectangle())
            .background(model.selectedDiskNodeURL == node.url ? Color.accentColor.opacity(0.08) : Color.clear)
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.secondary.opacity(0.12)), alignment: .bottom)
            .onTapGesture { performRowAction(clickCount: 1) }
            .accessibilityAddTraits(model.selectedDiskNodeURL == node.url ? .isSelected : [])

            if isExpanded {
                ForEach(children) { child in
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
            isExpanded.toggle()
        }
    }
}
