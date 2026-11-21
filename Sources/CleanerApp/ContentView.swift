import CleanerCore
import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    private let navigationPolicy = AppNavigationPolicy()

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section(L10n.text("清理")) {
                    ForEach([AppDestination.cleanupCenter, .systemCleanup, .applications, .largeFiles, .agentEnvironment, .localAIModels, .projects]) { destination in
                        destinationLabel(destination)
                    }
                }
                Section(L10n.text("工具")) {
                    ForEach([AppDestination.recovery, .settings]) { destination in
                        destinationLabel(destination)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationSplitViewColumnWidth(min: 210, ideal: 238)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SidebarDiskCapacityView(monitor: model.diskCapacityMonitor)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            }
            .background(SidebarSurface())
        } detail: {
            VStack(spacing: 0) {
                destinationView(for: model.selection).frame(
                    minWidth: 760,
                    maxWidth: .infinity,
                    minHeight: 560,
                    maxHeight: .infinity
                )
                .disabled((model.updateInProgress && model.selection != .settings) || model.checkingScanPermissions || model.trashEmptyingInProgress || model.projectRootsOperationInProgress)
                if showsOneClickBar {
                    OneClickCleanupActionBar(model: model)
                        .disabled(model.updateInProgress || model.trashEmptyingInProgress || model.projectRootsOperationInProgress)
                } else if showsDimensionActionBar {
                    DimensionActionBar(model: model)
                        .disabled(model.updateInProgress || model.trashEmptyingInProgress || model.projectRootsOperationInProgress)
                }
            }
            .navigationTitle("SuperCleaner")
        }
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
        .sheet(isPresented: Binding(
            get: { model.showsScanPermissionPreparation },
            set: { if !$0 { model.dismissScanPermissionPreparation() } }
        )) {
            ScanPermissionPreparationView(model: model)
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
        case .localAIModels: ResourceCleanupView(model: model, destination: .localAIModels)
        case .projects: ResourceCleanupView(model: model, destination: .projects)
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

private struct SidebarDiskCapacityView: View {
    @ObservedObject var monitor: DiskCapacityMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.text("磁盘空间"), systemImage: "internaldrive")
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
            if let capacity = monitor.snapshot {
                ProgressView(value: capacity.usedFraction)
                    .tint(.blue)
                    .accessibilityLabel(L10n.text("磁盘空间"))
                Text(L10n.text("可用空间：{0}", ByteCountFormatter.cleanerString(bytes: capacity.availableBytes)))
                    .monospacedDigit().lineLimit(1)
            } else if let error = monitor.readError {
                Label(L10n.text("无法读取磁盘空间"), systemImage: "exclamationmark.triangle")
                    .help(error)
            } else {
                Text(L10n.text("正在读取磁盘空间…"))
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
