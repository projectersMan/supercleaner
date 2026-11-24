import CleanerCore
import SwiftUI

struct ModelStorageRootsSettingsSection: View {
    @ObservedObject var model: AppModel
    @State private var roots: [ModelStorageRoot] = []
    @State private var provider = LocalAIModelProvider.huggingFace
    private var changed: Bool { model.modelScanRootsError != nil || Set(roots) != Set(model.modelScanRoots) }

    var body: some View {
        Section(L10n.text("模型扫描目录")) {
            Picker(L10n.text("模型工具"), selection: $provider) {
                ForEach(LocalAIModelProvider.allCases, id: \.self) { value in Text(value.displayName).tag(value) }
            }
            .help(L10n.text("固定目录继续扫描；自定义目录按所选工具的模型存储布局识别。"))
            HStack {
                Text(L10n.text("{0} 个扫描目录", String(roots.count)))
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button(L10n.text("添加目录…")) {
                    if let selected = model.selectModelRootFolders(provider: provider) {
                        roots = Array(Set(roots + selected)).sorted(by: Self.rootOrder)
                    }
                }
            }
            if !roots.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(roots) { root in
                            HStack(spacing: 10) {
                                Image(systemName: "folder").foregroundColor(.secondary)
                                Text(root.url.path).font(.caption.monospaced()).textSelection(.enabled)
                                    .lineLimit(1).truncationMode(.middle).help(root.url.path)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(root.provider.displayName).font(.caption).foregroundColor(.secondary)
                                Button(L10n.text("移除")) { roots.removeAll { $0.id == root.id } }
                                    .buttonStyle(.borderless)
                                    .help(L10n.text("仅移出扫描范围，不删除磁盘目录"))
                                    .accessibilityLabel(L10n.text("移除扫描目录 {0}", root.url.path))
                            }
                            .frame(height: 44)
                            .overlay(alignment: .bottom) { Divider() }
                        }
                    }
                }
                .frame(height: 132)
            }
            if changed {
                HStack {
                    Button(L10n.text("保存扫描目录")) { Task { await model.saveModelScanRoots(roots) } }
                    Button(L10n.text("撤销更改")) { roots = model.modelScanRoots }
                    Text(L10n.text("忙碌时保存，下次扫描生效。")).font(.caption).foregroundColor(.secondary)
                }
            }
            if let error = model.modelScanRootsError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundColor(.red)
                Button(L10n.text("重新读取目录配置")) { Task { await model.loadModelScanRoots() } }
            }
        }
        .disabled(model.modelRootsOperationInProgress || model.isDeletionInProgress)
        .task { await model.loadModelScanRoots(); roots = model.modelScanRoots }
        .onChange(of: model.modelScanRoots) { roots = $0 }
    }
    private static func rootOrder(_ left: ModelStorageRoot, _ right: ModelStorageRoot) -> Bool { left.id < right.id }
}
