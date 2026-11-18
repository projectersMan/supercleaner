public enum AppDestination: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case cleanupCenter
    case systemCleanup
    case applications
    case largeFiles
    case agentEnvironment
    case localAIModels
    case projects
    case recovery
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: L10n.text("概览")
        case .cleanupCenter: L10n.text("清理中心")
        case .systemCleanup: L10n.text("系统清理")
        case .applications: L10n.text("应用卸载")
        case .largeFiles: L10n.text("重复大文件")
        case .agentEnvironment: L10n.text("Agent 环境")
        case .localAIModels: L10n.text("本地 AI 模型")
        case .projects: L10n.text("项目产物")
        case .recovery: L10n.text("恢复记录")
        case .settings: L10n.text("设置")
        }
    }

    public var systemImage: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .cleanupCenter: "sparkles"
        case .systemCleanup: "trash"
        case .applications: "app.dashed"
        case .largeFiles: "doc.text.magnifyingglass"
        case .agentEnvironment: "terminal"
        case .localAIModels: "brain"
        case .projects: "shippingbox"
        case .recovery: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

public struct AppNavigationPolicy: Sendable {
    public enum EmptyStateAction: Sendable, Equatable {
        case returnToDashboard
        case none
    }

    public init() {}

    public let showsGlobalScanToolbar = false
    public let initialScanOwner = AppDestination.dashboard

    public func emptyStateAction(for destination: AppDestination) -> EmptyStateAction {
        switch destination {
        case .systemCleanup, .applications, .largeFiles, .agentEnvironment, .localAIModels, .projects: .returnToDashboard
        case .dashboard, .cleanupCenter, .recovery, .settings: .none
        }
    }

    public func showsDimensionActionBar(for destination: AppDestination) -> Bool {
        [.systemCleanup, .applications, .largeFiles, .agentEnvironment, .localAIModels, .projects].contains(destination)
    }

    public func showsModuleScanControls(
        for destination: AppDestination,
        globalScanIsRunning: Bool,
        moduleState: ScanModuleState?
    ) -> Bool {
        guard globalScanIsRunning, scanModule(for: destination) != nil else { return false }
        return moduleState == .waiting || moduleState == .scanning
    }

    public func usesCandidateReviewFocus(for destination: AppDestination) -> Bool {
        [.systemCleanup, .agentEnvironment, .localAIModels, .projects].contains(destination)
    }

    public func scanResultDestination(
        for module: ScanModuleID,
        state: ScanModuleState
    ) -> AppDestination? {
        guard [.completed, .limited].contains(state) else { return nil }
        switch module {
        case .general: return .systemCleanup
        case .applications: return .applications
        case .largeFiles: return .largeFiles
        case .agentEnvironment: return .agentEnvironment
        case .localAIModels: return .localAIModels
        case .projects: return .projects
        }
    }

    public func showsScanningPlaceholder(
        for destination: AppDestination,
        globalScanIsRunning: Bool,
        availableModules: Set<ScanModuleID>
    ) -> Bool {
        guard globalScanIsRunning, let module = scanModule(for: destination) else { return false }
        return !availableModules.contains(module)
    }

    private func scanModule(for destination: AppDestination) -> ScanModuleID? {
        switch destination {
        case .systemCleanup: .general
        case .applications: .applications
        case .largeFiles: .largeFiles
        case .agentEnvironment: .agentEnvironment
        case .localAIModels: .localAIModels
        case .projects: .projects
        case .dashboard, .cleanupCenter, .recovery, .settings: nil
        }
    }
}
