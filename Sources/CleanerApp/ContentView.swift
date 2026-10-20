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
            .navigationTitle("Cleaner")
            .navigationSplitViewColumnWidth(min: 210, ideal: 238)
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
        }
        .onAppear { model.bootstrap() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.helper.refresh()
            model.applicationDidBecomeActive()
        }
        .sheet(item: $model.deletionResult) { receipt in
            DeletionResultSheet(model: model, receipt: receipt)
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
        return model.phase == .scanning || model.systemReport != nil
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
