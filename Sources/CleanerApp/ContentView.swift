import CleanerCore
import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    private let navigationPolicy = AppNavigationPolicy()

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section(L10n.text("清理")) {
                    ForEach([AppDestination.cleanupCenter, .systemCleanup, .applications, .largeFiles, .agentEnvironment]) { destination in
                        destinationLabel(destination)
                    }
                }
                Section(L10n.text("工具")) {
                    ForEach([AppDestination.recovery, .settings]) { destination in
                        destinationLabel(destination)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 238)
            .background(SidebarToolbarAlignment())
        } detail: {
            VStack(spacing: 0) {
                destinationView(for: model.selection).frame(
                    minWidth: 760,
                    maxWidth: .infinity,
                    minHeight: 560,
                    maxHeight: .infinity
                )
                .disabled(model.updateInProgress && model.selection != .settings)
                if showsOneClickBar {
                    OneClickCleanupActionBar(model: model)
                        .disabled(model.updateInProgress)
                } else if showsDimensionActionBar {
                    DimensionActionBar(model: model)
                        .disabled(model.updateInProgress)
                }
            }
            .navigationTitle("SuperCleaner")
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onAppear { model.bootstrap() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.helper.refresh()
            model.applicationDidBecomeActive()
        }
        .sheet(isPresented: Binding(
            get: { model.showsDeletionSheet },
            set: { if !$0 { model.dismissDeletionSheet() } }
        )) {
            DeletionOperationSheet(model: model)
        }
        .alert(L10n.text("扫描权限提示"), isPresented: $model.showsPermissionIntroduction) {
            Button(L10n.text("打开系统设置…"), action: model.openFullDiskAccessSettings)
            Button(L10n.text("继续使用"), role: .cancel) {}
        } message: {
            Text(L10n.text("建议在系统设置中开启完全磁盘访问，以扫描更多位置。也可直接使用并跳过不可访问位置；App 管理在实际卸载时由系统确认。之后可在设置中调整，此提醒只显示一次。"))
        }
    }

    @ViewBuilder private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .dashboard: DashboardView(model: model)
        case .cleanupCenter: DashboardView(model: model)
        case .systemCleanup: CleanupReviewView(model: model, destination: .systemCleanup, title: L10n.text("系统清理"))
        case .applications: ApplicationsView(model: model)
        case .largeFiles: DiskSpaceView(model: model)
        case .agentEnvironment: AgentEnvironmentView(model: model)
        case .recovery: HistoryView(model: model)
        case .settings: PermissionsView(model: model)
        }
    }

    private var showsDimensionActionBar: Bool {
        navigationPolicy.showsDimensionActionBar(for: model.selection)
    }

    private var showsOneClickBar: Bool {
        guard model.selection == .cleanupCenter || model.selection == .dashboard else { return false }
        return model.isScanRunning || model.systemReport != nil
    }

    private func destinationLabel(_ destination: AppDestination) -> some View {
        HStack(spacing: 10) {
            Image(systemName: destination.systemImage)
                .frame(width: 18)
            Text(destination.title)
        }
        .tag(destination)
    }
}
