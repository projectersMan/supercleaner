import AppKit
import CleanerCore
import Sparkle

@MainActor enum ApplicationUpdateTerminationGuard {
    static var allowsTermination = true
}

/// Sparkle's ready screen must not leave an install queued for an unrelated quit.
/// Install now or cancel; preparation never implies permission to restart later.
@MainActor private final class ImmediateUpdateDriver: SPUStandardUserDriver {
    var confirmation: (() -> Bool)?
    var validateItem: ((SUAppcastItem) throws -> Void)?
    var rejected: ((Error) -> Void)?
    private var selectedItem: SUAppcastItem?
    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // Sparkle deliberately skips shouldProceedWithUpdate when resuming an
        // existing download/install. Our policy must apply to that path too.
        do { try validateItem?(appcastItem) }
        catch { rejected?(error); reply(.skip); return }
        selectedItem = appcastItem
        if state.stage == .installing {
            // No standard "later" choice for a resumed prepared installation:
            // Sparkle otherwise keeps it queued for an unrelated application quit.
            showReady(toInstallAndRelaunch: reply)
        } else {
            super.showUpdateFound(with: appcastItem, state: state, reply: reply)
        }
    }
    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if let confirmation { complete(confirmation(), reply: reply); return }
        let alert = NSAlert()
        alert.messageText = "安装更新并重新启动？"
        alert.informativeText = "更新已经下载并通过验证。现在安装将退出本应用；取消不会安排退出时安装。Helper 需要在新版设置中重新启用。"
        alert.addButton(withTitle: "安装并重新启动")
        alert.addButton(withTitle: "取消安装")
        complete(alert.runModal() == .alertFirstButtonReturn, reply: reply)
    }
    private func complete(_ approved: Bool, reply: (SPUUserUpdateChoice) -> Void) {
        if approved, let validateItem {
            do {
                guard let selectedItem else { throw ApplicationUpdateError.invalidArchive }
                try validateItem(selectedItem)
            } catch { rejected?(error); reply(.skip); return }
        }
        if approved { ApplicationUpdateTerminationGuard.allowsTermination = true }
        reply(approved ? .install : .skip)
    }
}

@MainActor final class ApplicationUpdateModel: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var isBusy = false
    @Published private(set) var message = "应用更新未配置；本地开发构建不会发起检查。"
    private var configuration: ReleaseConfiguration?
    private var updater: SPUUpdater?
    private var driver: ImmediateUpdateDriver?
    private var validationFailure: Error?
    private let canStart: @MainActor () -> Bool
    private let activityChanged: @MainActor (Bool) -> Void
    private let prepareHelper: @MainActor () async throws -> Void
    private let helperIsStopped: @MainActor () -> Bool

    init(canStart: @escaping @MainActor () -> Bool, activityChanged: @escaping @MainActor (Bool) -> Void,
         prepareHelper: @escaping @MainActor () async throws -> Void, helperIsStopped: @escaping @MainActor () -> Bool) {
        self.canStart = canStart; self.activityChanged = activityChanged
        self.prepareHelper = prepareHelper; self.helperIsStopped = helperIsStopped
        super.init()
        do {
            guard let config = try ReleaseConfiguration.load(), config.applicationUpdateURL != nil else { return }
            try ApplicationUpdatePolicy(configuration: config).validateBundleSettings(Bundle.main.infoDictionary ?? [:])
            let identity = try HelperSigningIdentity.current()
            guard identity.applicationIdentifier == config.bundleIdentifier, identity.teamIdentifier == config.teamIdentifier else { throw ReleaseConfigurationError.wrongApplication }
            configuration = config
            message = "仅手动检查与安装。升级开始前会解除 Helper 注册；取消或失败后可在设置中重新启用。"
        } catch { message = "应用更新不可用：\(error.localizedDescription)" }
    }
    var canCheck: Bool { configuration != nil && !isBusy && canStart() }
    var source: String? { configuration?.applicationUpdateURL?.host }

    /// Called only after an explicit confirmation covering Helper removal.
    func check() {
        guard canCheck else { return }
        isBusy = true; activityChanged(true)
        validationFailure = nil
        ApplicationUpdateTerminationGuard.allowsTermination = false
        message = "正在关闭特权会话并解除 Helper 注册…"
        Task {
            do {
                try await prepareHelper()
                guard helperIsStopped() else { throw ApplicationUpdateError.helperStillRegistered }
                if updater == nil {
                    let driver = ImmediateUpdateDriver(hostBundle: .main, delegate: nil)
                    driver.validateItem = { [weak self] item in
                        guard let self else { throw ApplicationUpdateError.busy }
                        try validate(item)
                    }
                    driver.rejected = { [weak self] error in self?.validationFailure = error }
                    self.driver = driver
                    let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
                    self.updater = updater
                    // Enforce policy even if older UserDefaults opted into
                    // automatic behavior. This runs only on the explicit action.
                    updater.automaticallyChecksForUpdates = false
                    updater.automaticallyDownloadsUpdates = false
                    updater.sendsSystemProfile = false
                    try updater.start()
                }
                message = "正在检查已签名应用更新；下载及安装需要在更新窗口中确认。"
                updater?.checkForUpdates()
            } catch { updater = nil; driver = nil; finish(error: error) }
        }
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        // Reject inherited UserDefaults enabling background checks. Only our
        // guarded user action may start a cycle, even after an older installation.
        guard isBusy, updateCheck == .updates, helperIsStopped() else { throw ApplicationUpdateError.busy }
        guard let configuration else { throw ReleaseConfigurationError.missing }
        try ApplicationUpdatePolicy(configuration: configuration).validateBundleSettings(Bundle.main.infoDictionary ?? [:])
    }
    func feedURLString(for updater: SPUUpdater) -> String? { configuration?.applicationUpdateURL?.absoluteString }
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate item: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard updateCheck == .updates else { throw ApplicationUpdateError.busy }
        try validate(item)
    }
    private func validate(_ item: SUAppcastItem) throws {
        guard isBusy, helperIsStopped(), let configuration else { throw ApplicationUpdateError.busy }
        try ApplicationUpdatePolicy(configuration: configuration).validate(
            version: item.versionString, currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            archiveURL: item.fileURL, length: item.contentLength, installationType: item.installationType,
            feedIsSigned: item.signingValidationStatus == .succeeded, isDelta: item.isDeltaUpdate)
    }
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate item: SUAppcastItem) -> Bool { false }
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        request.httpShouldHandleCookies = false
        request.setValue(nil, forHTTPHeaderField: "Cookie")
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        message = "正在下载并验证更新；可以在更新窗口中取消。"
    }
    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        message = "更新已验证；等待安装并重启的明确确认。"
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) { finish(error: error) }
    private func finish(error: Error?) {
        isBusy = false; activityChanged(false)
        ApplicationUpdateTerminationGuard.allowsTermination = true
        message = (error ?? validationFailure).map { "应用更新未完成：\($0.localizedDescription)。未自动重试；Helper 可在设置中重新启用。" }
            ?? "更新流程已结束。Helper 不会自动恢复特权，请在设置中按需启用。"
    }
    static func selfCheck(requireProduction: Bool = false) throws {
        defer { ApplicationUpdateTerminationGuard.allowsTermination = true }
        if let config = try ReleaseConfiguration.load(), config.applicationUpdateURL != nil {
            try ApplicationUpdatePolicy(configuration: config).validateBundleSettings(Bundle.main.infoDictionary ?? [:])
        }
        let framework = Bundle(for: SPUUpdater.self)
        guard framework.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "2.10.0" else { throw ReleaseConfigurationError.invalid }
        let driver = ImmediateUpdateDriver(hostBundle: .main, delegate: nil)
        for allow in [false, true] {
            ApplicationUpdateTerminationGuard.allowsTermination = false
            driver.confirmation = { allow }
            var replies = 0
            driver.showReady(toInstallAndRelaunch: { choice in
                precondition(choice == (allow ? .install : .skip)); replies += 1
            })
            precondition(replies == 1)
            precondition(ApplicationUpdateTerminationGuard.allowsTermination == allow)
        }
        let model = ApplicationUpdateModel(canStart: { false }, activityChanged: { _ in preconditionFailure("self-check started an update") },
            prepareHelper: { preconditionFailure("self-check touched Helper") }, helperIsStopped: { true })
        precondition(!model.canCheck && model.updater == nil && !model.isBusy)
        if requireProduction, model.configuration == nil { throw ReleaseConfigurationError.invalid }
        print("PASS: Sparkle 2.10.0 loaded; explicit ready/cancel choices; no update startup, network or Helper operation")
    }
}
