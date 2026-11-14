import CleanerCore
import SwiftUI

struct ApplicationsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
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
        .task {
            while !Task.isCancelled {
                model.refreshRunningApplications()
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    @ViewBuilder private var applicationContent: some View {
        if model.isLoadingApplications && model.applications.isEmpty {
            EmptyState(title: L10n.text("正在分析应用"), message: L10n.text("正在读取应用信息并建立可恢复卸载范围。"), icon: "arrow.clockwise")
        } else if model.applications.isEmpty {
            EmptyState(title: L10n.text("没有可展示的应用"), message: L10n.text("扫描没有发现可展示的应用；可查看扫描覆盖范围。"), icon: "app.dashed")
        } else if model.visibleApplications.isEmpty {
            EmptyState(title: L10n.text("没有匹配的应用"), message: model.applicationScope == .all
                ? L10n.text("调整搜索词或筛选范围；完整应用清单仍然保留。")
                : L10n.text("当前筛选范围内没有匹配项；切换“全部”可搜索完整应用清单，包括运行中和系统应用。"), icon: "magnifyingglass")
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                applicationSearch
                ApplicationScopePicker(selection: $model.applicationScope)
                    .frame(width: 420).fixedSize(horizontal: false, vertical: true)
                applicationSort
                Spacer(minLength: 0)
                applicationCount
                if model.applicationScope == .running || model.applicationScope == .all {
                    quitApplicationButton
                }
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    applicationSearch
                    Spacer(minLength: 0)
                    applicationCount
                }
                HStack(spacing: 12) {
                    ApplicationScopePicker(selection: $model.applicationScope)
                        .frame(width: 420).fixedSize(horizontal: false, vertical: true)
                    applicationSort
                    Spacer(minLength: 0)
                    if model.applicationScope == .running || model.applicationScope == .all {
                        quitApplicationButton
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.caption)
        .padding(.leading, 18)
        // Match SelectionActionBar's trailing inset.
        .padding(.trailing, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var quitApplicationButton: some View {
        let count = model.selectedApplicationsToQuit.count
        let title = model.quittingApplicationIDs.isEmpty
            ? L10n.text("退出应用")
            : L10n.text("正在退出…")
        return Button { model.quitSelectedApplications() } label: {
            Text(title).lineLimit(1)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.quittingApplicationIDs.isEmpty || count == 0)
        .help(L10n.text("勾选运行中的应用后批量请求正常退出；不会强制结束或卸载应用。"))
        .accessibilityLabel(title)
    }

    private var applicationSearch: some View {
        TextField(L10n.text("搜索名称、Bundle ID 或路径"), text: $model.applicationQuery)
            .textFieldStyle(.roundedBorder)
            .frame(width: 260)
    }

    private var applicationSort: some View {
        Picker(L10n.text("排序"), selection: $model.applicationSortOrder) {
            ForEach(ApplicationSortOrder.allCases, id: \.self) { order in
                Text(order.displayTitle).tag(order)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 140)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var applicationCount: some View {
        let summary = model.applicationFilterSummary
        return Text(L10n.text("{0} / {1} 个应用", String(describing: summary.visibleCount), String(describing: summary.totalCount)))
            .monospacedDigit().foregroundColor(.secondary)
            .frame(width: 140, alignment: .trailing)
            .lineLimit(1)
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
    private var receiptItems: [URL] {
        model.uninstallReceiptItems(for: application)
    }
    private var selectableBytes: UInt64 { selectableItems.reduce(0) { $0 + $1.candidate.bytes } }
    private var selectableSizeDescription: String {
        ByteCountFormatter.cleanerString(bytes: selectableBytes)
    }
    fileprivate static func isSelectable(_ item: UninstallItem) -> Bool {
        item.candidate.risk.isSelectable && !item.candidate.isActive && !item.isShared
    }
    private var hasSelectedItems: Bool {
        plan.map { model.uninstallSelectionState(for: $0) != .none } == true
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                planCheckbox
                Button {
                    model.selectedApplicationID = application.id
                    disclosure.toggle()
                } label: {
                    Image(systemName: disclosure.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).frame(width: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(disclosure.isExpanded ? L10n.text("折叠 {0}", String(describing: application.name)) : L10n.text("展开 {0}", String(describing: application.name)))

                ApplicationIconView(bundleURL: application.bundleURL, version: application.version)
                VStack(alignment: .leading, spacing: 3) {
                    Text(application.name).fontWeight(.semibold).lineLimit(1)
                    Text(application.bundleIdentifier).font(.caption.monospaced()).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 16)
                if application.isUninstallProtected {
                    Label(L10n.text("受保护"), systemImage: "lock.shield")
                        .font(.callout.weight(.medium)).foregroundColor(.secondary)
                } else if plan != nil {
                    Text(L10n.text("可卸载 {0} 项 · {1}", String(describing: selectableItems.count + receiptItems.count), String(describing: selectableSizeDescription)))
                        .font(.callout.weight(.medium))
                        .frame(minWidth: 150, alignment: .trailing)
                }
                if analysis == nil && !application.isRunning && !application.isUninstallProtected {
                    Label(L10n.text("正在准备卸载清单…"), systemImage: "clock")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let analysis, application.isRunning && !application.isUninstallProtected {
                    AnalysisStateBadge(analysis: analysis)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { performRowAction(clickCount: 1) }

            if let message = model.applicationQuitMessages[application.id] {
                Text(message).font(.caption).foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 66).padding(.trailing, 18).padding(.bottom, 10)
            }

            if disclosure.isExpanded {
                Divider().padding(.leading, 52)
                if let plan {
                    expandedContent(plan: plan)
                } else {
                    protectedContent
                }
                // Uninstallable rows consistently show the uninstall inventory,
                // not observations retained from when the application was running.
                if model.applicationScope != .uninstallable {
                    deepScanContent
                }
                if let ownership = analysis?.ownership { ownershipContent(ownership) }
            }
        }
        .background(hasSelectedItems || isHovered || model.quitSelectedApplicationIDs.contains(application.id)
            ? Color.accentColor.opacity(0.08) : Color.clear)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.primary.opacity(0.08)), alignment: .bottom)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.16), value: disclosure.isExpanded)
        .accessibilityAddTraits(hasSelectedItems || model.quitSelectedApplicationIDs.contains(application.id) ? .isSelected : [])
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
            ForEach(ownership.copies, id: \.self) { copy in
                Label(L10n.text("其他副本：{0}", String(describing: copy.path)), systemImage: "doc.on.doc").font(.caption2).textSelection(.enabled)
            }
            ForEach(ownership.serviceReferences ?? []) { reference in
                Label(L10n.text(reference.file.standardizedFileURL.path.hasPrefix(application.id.standardizedFileURL.path + "/")
                    ? "内嵌组件：{0}（随主应用卸载，大小已包含）" : "服务引用：{0}", reference.file.path), systemImage: "gearshape.2").font(.caption2).textSelection(.enabled)
            }
            ForEach(ownership.installation.receipts.filter { !receiptItems.contains($0) }, id: \.self) { receipt in
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
        if application.isUninstallProtected {
            Color.clear.frame(width: 18, height: 1)
        } else if application.isRunning {
            let checked = model.quitSelectedApplicationIDs.contains(application.id)
            Button { model.toggleApplicationQuitSelection(application) } label: {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.title3).foregroundColor(checked ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!model.quittingApplicationIDs.isEmpty || (!checked && !model.canQuitApplication(application)))
            .help(L10n.text("勾选以退出此应用，不会选择卸载内容"))
            .accessibilityLabel(L10n.text("选择退出 {0}", application.name))
            .accessibilityValue(checked ? L10n.text("已选择") : L10n.text("未选择"))
        } else if let plan, !plan.selectableItemIDs.isEmpty || !receiptItems.isEmpty {
            let checked = model.uninstallSelectionState(for: plan) == .all
            Button { model.toggleUninstall(plan) } label: {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.title3).foregroundColor(checked ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(model.isDeletionInProgress)
            .help(checked ? L10n.text("取消选择此应用的可卸载项目") : L10n.text("手动选择此应用的全部可卸载项目"))
        } else if analysis != nil {
            Color.clear.frame(width: 18, height: 1)
        } else {
            Color.clear.frame(width: 18, height: 1)
        }
    }

    private func expandedContent(plan: UninstallPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(selectableItems) { item in
                UninstallItemRow(model: model, item: item).padding(.leading, 52)
                if item.id != selectableItems.last?.id || !receiptItems.isEmpty { Divider().padding(.leading, 92) }
            }
            ForEach(receiptItems, id: \.self) { receipt in
                if let packageID = PackageReceiptCleanupSelection.packageID(for: receipt) {
                    UninstallReceiptRow(model: model, receipt: receipt, packageID: packageID)
                        .padding(.leading, 52)
                    if receipt != receiptItems.last { Divider().padding(.leading, 92) }
                }
            }
        }
        .background(Color.primary.opacity(0.018))
    }

    private var protectedContent: some View {
        HStack(alignment: .top, spacing: 10) {
            if analysis != nil {
                Image(systemName: application.isUninstallProtected ? "lock.shield" : application.isRunning ? "pause.circle.fill" : "info.circle")
                    .foregroundColor(application.isRunning && !application.isUninstallProtected ? .orange : .secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                if let analysis {
                    Text(analysis.statusTitle).font(.callout.weight(.semibold))
                    Text(analysis.message ?? L10n.text("当前扫描没有生成可执行的卸载项目。"))
                        .font(.caption).foregroundColor(.secondary)
                }
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
        if item.candidate.evidence.contains(where: { $0.code == "size-not-measured" }) { return "—" }
        return ByteCountFormatter.cleanerString(bytes: item.candidate.bytes)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { model.toggleUninstall(item) } label: {
                Image(systemName: model.isUninstallItemSelected(item) ? "checkmark.square.fill" : "square")
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

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct UninstallReceiptRow: View {
    @ObservedObject var model: AppModel
    let receipt: URL
    let packageID: String

    private var isSelected: Bool { model.packageReceiptSelection.isSelected(packageID) }

    var body: some View {
        HStack(spacing: 12) {
            Button { model.setPackageReceiptSelected(!isSelected, packageID: packageID) } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.body).foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(model.isDeletionInProgress)
            .accessibilityLabel(receipt.lastPathComponent)
            VStack(alignment: .leading, spacing: 3) {
                Text(receipt.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
                Text(receipt.path).font(.caption2.monospaced()).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Text("—")
                .font(.caption).foregroundColor(.secondary).frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct AnalysisStateBadge: View {
    let analysis: ApplicationUninstallAnalysis
    var body: some View {
        let value = presentation
        if analysis.state != .protected {
            Label(analysis.statusTitle, systemImage: value.icon)
                .font(.caption.weight(.semibold)).foregroundColor(value.color)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(value.color.opacity(0.12), in: Capsule()).frame(minWidth: 104)
        }
    }
    private var presentation: (icon: String, color: Color) {
        switch analysis.state {
        case .complete: return ("checkmark.shield", .green)
        case .limited: return ("exclamationmark.triangle", .orange)
        case .running: return ("pause.circle.fill", .orange)
        case .protected: return ("info.circle", .secondary)
        case .unavailable: return ("xmark.octagon", .red)
        }
    }
}
