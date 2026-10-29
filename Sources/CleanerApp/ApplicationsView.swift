import CleanerCore
import SwiftUI

struct ApplicationsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("应用卸载")).font(.largeTitle.bold())
                Text(L10n.text("基础扫描识别应用归属；运行观察补充关联线索。展开核对后选择卸载内容，用户数据需手动确认。"))
                    .foregroundColor(.secondary)
            }
            .padding(24)
            Divider()
            if !model.hasScanResult(for: .applications) {
                ScanRequiredView(destinationTitle: L10n.text("应用卸载")) { model.navigateToScan() }
            } else {
                applicationToolbar
                Divider()
                applicationContent
            }
        }
    }

    @ViewBuilder private var applicationContent: some View {
        if model.isLoadingApplications && model.applications.isEmpty {
            EmptyState(title: L10n.text("正在分析应用"), message: L10n.text("正在读取应用信息并建立可恢复卸载范围。"), icon: "arrow.clockwise")
        } else if model.applications.isEmpty {
            EmptyState(title: L10n.text("没有可展示的应用"), message: L10n.text("扫描没有发现可展示的应用；可查看扫描覆盖范围。"), icon: "app.dashed")
        } else if model.visibleApplications.isEmpty {
            EmptyState(title: L10n.text("没有匹配的应用"), message: L10n.text("调整搜索词或筛选范围；完整应用清单仍然保留。"), icon: "magnifyingglass")
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.visibleApplications) { application in
                        ApplicationUninstallRow(model: model, application: application, analysis: model.uninstallAnalysis(for: application))
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 8)
            }
        }
    }

    private var applicationToolbar: some View {
        HStack(spacing: 12) {
            TextField(L10n.text("搜索名称、Bundle ID 或路径"), text: $model.applicationQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)
            Picker(L10n.text("范围"), selection: $model.applicationScope) {
                ForEach(ApplicationListScope.allCases, id: \.self) { scope in Text(scope.displayTitle).tag(scope) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            Picker(L10n.text("排序"), selection: $model.applicationSortOrder) {
                ForEach(ApplicationSortOrder.allCases, id: \.self) { order in
                    Text(order.displayTitle).tag(order)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            Text(L10n.text("{0} / {1} 个应用", String(describing: model.applicationFilterSummary.visibleCount), String(describing: model.applicationFilterSummary.totalCount)))
                .font(.caption).foregroundColor(.secondary).fixedSize()
            Spacer()
            Button { model.refreshApplications() } label: {
                Label(model.isLoadingApplications ? L10n.text("分析中") : L10n.text("刷新应用"), systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoadingApplications || model.deepScanningApplicationID != nil || model.isScanRunning || model.phase == .executing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct ApplicationUninstallRow: View {
    @ObservedObject var model: AppModel
    let application: InstalledApplication
    let analysis: ApplicationUninstallAnalysis?
    @State private var disclosure = ApplicationUninstallDisclosureState()
    @State private var confirmUninstaller = false
    @State private var confirmDeepScan = false
    @State private var isHovered = false

    private var plan: UninstallPlan? { analysis?.plan }
    /// Keep the summary count and size aligned with rows that show an enabled checkbox.
    private var selectableItems: [UninstallItem] {
        guard let plan else { return [] }
        return plan.items.filter(Self.isSelectable)
    }
    private var selectableBytes: UInt64 { selectableItems.reduce(0) { $0 + $1.candidate.bytes } }
    private var selectableSizeDescription: String {
        let estimated = selectableItems.contains { $0.candidate.evidence.contains { $0.code == "size-estimate" } }
        return (estimated ? L10n.text("至少 ") : "") + ByteCountFormatter.cleanerString(bytes: selectableBytes)
    }
    fileprivate static func isSelectable(_ item: UninstallItem) -> Bool {
        item.candidate.risk.isSelectable && !item.candidate.isActive && !item.isShared
    }
    private var hasSelectedItems: Bool {
        plan?.items.contains(where: { model.uninstallSelectedIDs.contains($0.id) }) == true
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                planCheckbox
                Button { disclosure.toggle() } label: {
                    Image(systemName: disclosure.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).frame(width: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(disclosure.isExpanded ? L10n.text("折叠 {0}", String(describing: application.name)) : L10n.text("展开 {0}", String(describing: application.name)))

                ApplicationIconView(bundleURL: application.bundleURL, version: application.version)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(application.name).fontWeight(.semibold).lineLimit(1)
                        if application.isRunning {
                            Label(L10n.text("运行中"), systemImage: "circle.fill").font(.caption2.weight(.semibold)).foregroundColor(.green)
                        }
                    }
                    Text(application.bundleIdentifier).font(.caption.monospaced()).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 16)
                if plan != nil {
                    Text(L10n.text("可卸载 {0} 项 · {1}", String(describing: selectableItems.count), String(describing: selectableSizeDescription)))
                        .font(.callout.weight(.medium))
                        .frame(minWidth: 150, alignment: .trailing)
                }
                AnalysisStateBadge(analysis: analysis)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { performRowAction(clickCount: 1) }

            if disclosure.isExpanded {
                Divider().padding(.leading, 52)
                if let plan {
                    expandedContent(plan: plan)
                } else {
                    protectedContent
                }
                deepScanContent
                if let ownership = analysis?.ownership { ownershipContent(ownership) }
            }
        }
        .background(hasSelectedItems || isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.primary.opacity(0.08)), alignment: .bottom)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.16), value: disclosure.isExpanded)
        .accessibilityAddTraits(hasSelectedItems ? .isSelected : [])
        .alert(L10n.text("启动应用进行深度关联扫描？"), isPresented: $confirmDeepScan) {
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("启动并观察")) { model.startApplicationDeepScan(application, allowLaunch: true) }
        } message: {
            Text(L10n.text("会尝试在后台真正启动此应用，短暂观察它打开的文件；应用仍可能显示窗口、联网或修改数据。结束后只请求退出本次启动的实例，不会强制退出。采样不能证明全部文件已发现。"))
        }
        .alert(L10n.text("打开官方卸载器？"), isPresented: $confirmUninstaller) {
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("打开")) {
                if let url = analysis?.ownership?.installation.officialUninstaller {
                    model.openOfficialUninstaller(for: application, expectedURL: url)
                }
            }
        } message: {
            Text(L10n.text("会再次验证应用与卸载器签名。官方工具的修改不属于本应用的隔离恢复；请在工具内确认具体操作。"))
        }
    }

    private var deepScanContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !application.isSystem {
                HStack {
                    if model.deepScanningApplicationID == application.id {
                        Button(L10n.text("停止观察")) { model.cancelApplicationDeepScan() }
                        ProgressView().controlSize(.small)
                    } else {
                        Button(L10n.text("深度关联扫描")) {
                            if application.isRunning { model.startApplicationDeepScan(application, allowLaunch: false) }
                            else { confirmDeepScan = true }
                        }
                        .disabled(!model.canStartApplicationDeepScan)
                    }
                    Text(L10n.text("仅采样当前打开的文件，不能据此直接删除。"))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if let message = model.deepScanMessages[application.id] {
                Text(message).font(.caption).foregroundColor(.secondary)
            }
            if let observation = analysis?.runtimeObservation {
                Text(observation.summary).font(.caption).foregroundColor(.secondary)
                ForEach(observation.directories, id: \.self) { directory in
                    HStack(alignment: .top) {
                        Image(systemName: "eye")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(directory.path).font(.caption.monospaced()).textSelection(.enabled)
                            Text(observationLabel(for: directory))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(L10n.text("在访达中查看")) { NSWorkspace.shared.activateFileViewerSelecting([directory]) }
                            .font(.caption)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 66).padding(.trailing, 18).padding(.vertical, 10)
    }

    private func observationLabel(for directory: URL) -> String {
        if let item = analysis?.plan?.items.first(where: { $0.candidate.url.standardizedFileURL.path == directory.standardizedFileURL.path }) {
            return ApplicationUninstallRow.isSelectable(item)
                ? L10n.text("已列入上方卸载清单，可勾选删除")
                : L10n.text("已列入上方清单，请查看该项的保护原因")
        }
        return L10n.text("观察到访问 · 可删除性以卸载清单的归属校验为准")
    }

    private func ownershipContent(_ ownership: ApplicationOwnershipNode) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.text("安装来源：{0}", String(describing: ownership.installation.title))).font(.caption.weight(.semibold))
            Text(ownership.guidance).font(.caption).foregroundColor(.secondary)
            ForEach(ownership.copies, id: \.self) { copy in
                Label(L10n.text("其他副本：{0}", String(describing: copy.path)), systemImage: "doc.on.doc").font(.caption2).textSelection(.enabled)
            }
            ForEach(ownership.serviceReferences ?? []) { reference in
                Label(L10n.text("服务引用：{0}", String(describing: reference.file.path)), systemImage: "gearshape.2").font(.caption2).textSelection(.enabled)
            }
            ForEach(ownership.installation.receipts, id: \.self) { receipt in
                Button(L10n.text("查看收据：{0}", String(describing: receipt.lastPathComponent))) { NSWorkspace.shared.activateFileViewerSelecting([receipt]) }
                    .font(.caption).buttonStyle(.link)
            }
            if let command = ownership.installation.packageManagerCommand {
                HStack {
                    Text(command).font(.caption.monospaced()).textSelection(.enabled)
                    Button(L10n.text("复制命令")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string) }
                }
            }
            if ownership.installation.source == .steam {
                Button(L10n.text("在访达中查看游戏")) { NSWorkspace.shared.activateFileViewerSelecting([application.id]) }.font(.caption)
            }
            if ownership.installation.officialUninstaller != nil {
                Button(L10n.text("打开官方卸载器…")) { confirmUninstaller = true }
                    .disabled(model.isScanRunning || model.phase == .executing)
            }
            if !ownership.configurationReferences.isEmpty {
                Text(L10n.text("配置引用（保留配置，仅报告位置）")).font(.caption.weight(.semibold))
                ForEach(ownership.configurationReferences.prefix(20)) { reference in
                    Text("\(reference.file.path):\(reference.line)").font(.caption2.monospaced()).textSelection(.enabled)
                }
                if ownership.configurationReferences.count > 20 { Text(L10n.text("另有 {0} 处引用", String(describing: ownership.configurationReferences.count - 20))).font(.caption2) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 66).padding(.trailing, 18).padding(.bottom, 12)
    }

    private func performRowAction(clickCount: Int) {
        model.selectedApplicationID = application.id
        if ApplicationUninstallRowInteraction.action(clickCount: clickCount) == .selectAndToggleExpansion {
            disclosure.toggle()
        }
    }

    @ViewBuilder private var planCheckbox: some View {
        if let plan, !plan.selectableItemIDs.isEmpty {
            let state = model.uninstallSelectionState(for: plan)
            Button { model.toggleUninstall(plan) } label: {
                Image(systemName: state == .all ? "checkmark.square.fill" : state == .partial ? "minus.square.fill" : "square")
                    .font(.title3).foregroundColor(state == .none ? .secondary : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(model.isDeletionInProgress)
            .help(state == .all ? L10n.text("取消选择此应用的可卸载项目") : L10n.text("手动选择此应用的全部可卸载项目"))
        } else {
            Image(systemName: "lock.square").font(.title3).foregroundColor(.secondary).frame(width: 18)
                .help(analysis?.message ?? L10n.text("当前应用没有可选择的卸载项目"))
        }
    }

    private func expandedContent(plan: UninstallPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: analysis?.state == .limited ? "exclamationmark.triangle" : "info.circle")
                    .foregroundColor(analysis?.state == .limited ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(application.bundleURL.path).font(.caption.monospaced()).textSelection(.enabled)
                    Text(analysis?.message ?? L10n.text("可选择移除经确认独占的用户数据和关联文件；共享内容、系统资源及仍有引用的项目继续保护。"))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 54)
            .padding(.vertical, 10)
            if let limitations = analysis?.limitations, !limitations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(limitations.prefix(8)) { limitation in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(limitation.title).font(.caption.weight(.semibold)).foregroundColor(.orange)
                            if let path = limitation.path {
                                Text(path.path).font(.caption2.monospaced()).textSelection(.enabled)
                            }
                            Text(limitation.impact).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    if limitations.count > 8 {
                        Text(L10n.text("另有 {0} 个位置未完整统计。", String(describing: limitations.count - 8)))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 54)
                .padding(.bottom, 10)
            }
            ForEach(plan.items) { item in
                UninstallItemRow(model: model, item: item).padding(.leading, 52)
                if item.id != plan.items.last?.id { Divider().padding(.leading, 92) }
            }
        }
        .background(Color.primary.opacity(0.018))
    }

    private var protectedContent: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: application.isRunning ? "pause.circle.fill" : "lock.shield.fill")
                .foregroundColor(application.isRunning ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(analysis?.statusTitle ?? L10n.text("当前不可卸载")).font(.callout.weight(.semibold))
                Text(analysis?.message ?? L10n.text("当前扫描没有生成可执行的卸载项目。"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(application.bundleURL.path)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.leading, 54)
        .padding(.trailing, 18)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.018))
    }
}

private struct UninstallItemRow: View {
    @ObservedObject var model: AppModel
    let item: UninstallItem
    private var isSelectable: Bool { ApplicationUninstallRow.isSelectable(item) }
    private var sizeDescription: String {
        if item.candidate.evidence.contains(where: { $0.code == "size-not-measured" }) { return L10n.text("未统计") }
        let estimated = item.candidate.evidence.contains { $0.code == "size-estimate" }
        return (estimated ? L10n.text("至少 ") : "") + ByteCountFormatter.cleanerString(bytes: item.candidate.bytes)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { model.toggleUninstall(item) } label: {
                Image(systemName: model.isUninstallItemSelected(item) ? "checkmark.square.fill" : isSelectable ? "square" : "lock.square")
                    .font(.body).foregroundColor(model.isUninstallItemSelected(item) ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable || model.isDeletionInProgress)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.candidate.category == .application
                    ? L10n.text("{0} · 应用本体", String(describing: item.candidate.displayName))
                    : item.candidate.displayName)
                    .font(.callout.weight(.medium)).lineLimit(1)
                Text(item.candidate.url.path).font(.caption2.monospaced()).foregroundColor(.secondary).lineLimit(1)
                if let diagnostic = item.candidate.evidence.first(where: { $0.code == "diagnostic-file" }) {
                    Text(diagnostic.summary).font(.caption2).foregroundColor(.secondary)
                }
                if let declaration = item.candidate.evidence.first(where: { $0.code == "data-declaration-source" }) {
                    Text(L10n.text("应用包声明的数据目录 · 用户数据需手动确认"))
                        .font(.caption2).foregroundColor(.secondary).help(declaration.summary)
                }
            }
            Spacer()
            Text(sizeDescription)
                .font(.caption).foregroundColor(.secondary).frame(minWidth: 72, alignment: .trailing)
            ItemProtectionBadge(item: item, isSelected: model.isUninstallItemSelected(item))
                .help(item.candidate.evidence.first { $0.code == "protection-reason" }?.summary
                    ?? item.candidate.evidence.first { $0.code == "service-definition" }?.summary
                    ?? L10n.text("可手动加入卸载计划"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct AnalysisStateBadge: View {
    let analysis: ApplicationUninstallAnalysis?
    var body: some View {
        let value = presentation
        Label(analysis?.statusTitle ?? value.title, systemImage: value.icon)
            .font(.caption.weight(.semibold)).foregroundColor(value.color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(value.color.opacity(0.12), in: Capsule()).frame(minWidth: 104)
    }
    private var presentation: (title: String, icon: String, color: Color) {
        switch analysis?.state {
        case .complete: return (L10n.text("分析完整"), "checkmark.shield", .green)
        case .limited: return (L10n.text("分析受限"), "exclamationmark.triangle", .orange)
        case .protected where analysis?.application.isRunning == true:
            return (L10n.text("运行中 · 暂不可卸载"), "pause.circle.fill", .orange)
        case .protected: return (L10n.text("系统保护"), "lock.fill", .secondary)
        case .unavailable: return (L10n.text("无法分析"), "xmark.octagon", .red)
        case nil: return (L10n.text("等待分析"), "clock", .secondary)
        }
    }
}

private struct ItemProtectionBadge: View {
    let item: UninstallItem
    let isSelected: Bool
    var body: some View {
        let protected = item.isShared || !item.candidate.risk.isSelectable || item.candidate.isActive
        let isSelectable = ApplicationUninstallRow.isSelectable(item)
        let reason = item.candidate.evidence.first { $0.code == "protection-reason" }?.summary ?? ""
        let isService = item.candidate.evidence.contains { $0.code == "service-definition" }
        let isExternal = item.candidate.evidence.contains { $0.code == "external-uninstall" }
        let isReferenceOnly = item.candidate.evidence.contains { $0.code == "association-reference-only" }
        let isSystem = reason.contains(L10n.text("系统目录"))
        let isReferenced = reason.contains(L10n.text("引用"))
        let title = item.isShared ? L10n.text("其他应用共用")
            : isService ? L10n.text("需先停止服务")
            : isExternal && !isSelectable ? L10n.text("请使用原安装器")
            : isSystem ? L10n.text("系统目录保护")
            : isReferenceOnly ? L10n.text("仅关联展示")
            : isReferenced ? L10n.text("仍有项目引用")
            : protected ? L10n.text("归属待确认")
            : isSelected ? L10n.text("已选择") : nil
        let color: Color = protected ? .secondary : isSelected ? .green : item.containsUserData ? .blue : .orange
        if let title {
            Label(title, systemImage: protected ? "lock.fill" : "checkmark.circle.fill")
                .font(.caption2.weight(.semibold)).foregroundColor(color)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(color.opacity(0.11), in: Capsule()).frame(minWidth: 76)
        }
    }
}
