import AppKit
import CleanerCore
import Foundation
import SwiftUI

@MainActor final class CommercialSettingsModel: ObservableObject {
    @Published var email = ""
    @Published var licenseKey = ""
    @Published private(set) var snapshot: CommercialSnapshot?
    @Published private(set) var devices: [CommercialDevice] = []
    @Published private(set) var message: String?
    @Published private(set) var error: String?
    @Published private(set) var isBusy = false
    @Published private(set) var isPolling = false
    private let access: CommercialAccess
    private var pollingTask: Task<Bool, Error>?

    init(access: CommercialAccess) { self.access = access }

    func showAuthorizationFailure(_ message: String) { error = message }

    func load() async {
        let result = await Task { try await access.snapshot() }.result
        applySnapshot(result)
    }

    func refreshAutomatically() async {
        let result = await Task { try await access.refreshIfNeeded() }.result
        switch result {
        case let .success(refreshed):
            if refreshed {
                error = nil
                message = L10n.text("离线授权已自动刷新。")
            }
        case let .failure(failure): error = failure.localizedDescription
        }
        await load()
    }

    func purchase() {
        perform { [self] in
            let checkout = try await access.purchase(email: email)
            guard NSWorkspace.shared.open(checkout) else {
                throw CommercialClientError(message: L10n.text("无法打开系统浏览器，请检查默认浏览器设置。"))
            }
            return L10n.text("已打开支付宝收银台；付款后点击检查支付，客户端只认服务端确认。")
        }
    }

    func activate() {
        perform { [self] in
            try await access.activate(email: email, licenseKey: licenseKey, deviceName: CommercialAccess.currentDeviceName)
            licenseKey = ""
            return L10n.text("买断授权已激活。")
        }
    }

    func refresh() {
        perform { [self] in
            try await access.refresh(deviceName: CommercialAccess.currentDeviceName)
            return L10n.text("离线授权已刷新。")
        }
    }

    func copyActivationCode() {
        perform { [self] in
            let key = try await access.activationCodeForCopy()
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(key, forType: .string) else {
                throw CommercialClientError(message: L10n.text("无法复制激活码，请检查系统剪贴板。"))
            }
            return L10n.text("激活码已复制；仅用于你的另一台设备，请勿分享。")
        }
    }

    func loadDevices() {
        perform { [self] in
            devices = try await access.devices()
            return L10n.text("设备列表已更新。")
        }
    }

    func deactivate(_ deviceID: UUID) {
        perform { [self] in
            try await access.deactivate(deviceID)
            devices = try await access.devices()
            return L10n.text("设备已解绑；其它设备已有离线凭据将在其期限结束后失效。")
        }
    }

    func checkPayment() {
        guard !isBusy, !isPolling else { return }
        isPolling = true
        error = nil
        let task = Task { [self] in try await pollPayment() }
        pollingTask = task
        Task { [weak self] in
            guard let self else { return }
            let result = await task.result
            switch result {
            case let .success(paid): message = paid ? L10n.text("买断授权已激活。") : L10n.text("暂未确认付款；订单已保留，可稍后再次检查。")
            case let .failure(failure):
                if !(failure is CancellationError), (failure as? URLError)?.code != .cancelled {
                    error = failure.localizedDescription
                }
            }
            await load()
            isPolling = false
            pollingTask = nil
        }
    }

    func stopPolling() { pollingTask?.cancel() }

    private func pollPayment() async throws -> Bool {
        for _ in 0..<40 {
            try Task.checkCancellation()
            if try await access.checkPayment(deviceName: CommercialAccess.currentDeviceName) { return true }
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
        return false
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> String) {
        guard !isBusy, !isPolling else { return }
        isBusy = true
        error = nil
        message = nil
        Task { [weak self] in
            guard let self else { return }
            let result = await Task { try await operation() }.result
            switch result {
            case let .success(text): message = text
            case let .failure(failure): error = failure.localizedDescription
            }
            await load()
            isBusy = false
        }
    }

    private func applySnapshot(_ result: Result<CommercialSnapshot, Error>) {
        switch result {
        case let .success(current):
            snapshot = current
            if email.isEmpty { email = current.email ?? "" }
        case let .failure(failure): error = failure.localizedDescription
        }
    }
}

struct CommercialSettingsSection: View {
    @ObservedObject var model: CommercialSettingsModel
    @State private var deviceToDeactivate: CommercialDevice?
    let operationsBusy: Bool

    var body: some View {
        Section(L10n.text("买断授权")) {
            Text(L10n.text("一次性 ¥9.99，每份授权最多激活 2 台设备。无订阅、无自动续费。"))
            Text(L10n.text("买断权益永久有效；离线凭据有效期 7 天，联网时自动续期。恢复、历史、导出回执和移除 Helper 始终可用。"))
                .font(.caption).foregroundColor(.secondary)
            if let snapshot = model.snapshot, let until = snapshot.offlineValidUntil {
                LabeledContent(L10n.text("离线凭据有效至")) { Text(until, style: .date) + Text(" ") + Text(until, style: .time) }
                if until <= Date() {
                    Text(L10n.text("离线凭据已到期，请联网刷新；买断权益没有到期。"))
                        .font(.caption).foregroundColor(.orange)
                }
            } else {
                Text(L10n.text("尚未激活；扫描和新清理需要买断授权。"))
                    .font(.caption).foregroundColor(.secondary)
            }
            TextField(L10n.text("购买邮箱"), text: $model.email)
            SecureField(L10n.text("激活码"), text: $model.licenseKey)
            HStack {
                Button(L10n.text("支付宝购买…")) { model.purchase() }
                Button(L10n.text("激活授权")) { model.activate() }
                Button(L10n.text("刷新离线授权")) { model.refresh() }
                Button(L10n.text("管理已激活设备")) { model.loadDevices() }
            }
            .disabled(model.isBusy || model.isPolling || operationsBusy)
            Button(L10n.text("复制激活码以激活另一台 Mac")) { model.copyActivationCode() }
            .disabled(model.isBusy || model.isPolling || operationsBusy)
            if model.snapshot?.hasPendingOrder == true {
                HStack {
                    Button(L10n.text("检查支付并激活")) { model.checkPayment() }
                        .disabled(model.isBusy || model.isPolling || operationsBusy)
                    if model.isPolling {
                        ProgressView().controlSize(.small)
                        Button(L10n.text("停止检查")) { model.stopPolling() }
                    }
                }
            }
            ForEach(model.devices) { device in
                HStack {
                    VStack(alignment: .leading) {
                        Text(device.deviceName)
                        Text(device.deviceID.uuidString).font(.caption.monospaced()).foregroundColor(.secondary)
                    }
                    if device.deviceID == model.snapshot?.deviceID { Text(L10n.text("本机")).font(.caption).foregroundColor(.secondary) }
                    Spacer()
                    Button(L10n.text("解绑设备…")) { deviceToDeactivate = device }
                        .disabled(model.isBusy || model.isPolling || operationsBusy)
                }
            }
            if let message = model.message { Text(message).font(.caption).textSelection(.enabled) }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundColor(.red).textSelection(.enabled)
            }
            Text(L10n.text("网络失败不会删除仍然有效的离线凭据。解绑本机会立即移除本机凭据；重新激活需要设备名额。"))
                .font(.caption).foregroundColor(.secondary)
        }
        .task { await model.load() }
        .confirmationDialog(L10n.text("解绑此设备？"), isPresented: Binding(
            get: { deviceToDeactivate != nil }, set: { if !$0 { deviceToDeactivate = nil } }
        )) {
            if let device = deviceToDeactivate {
                Button(L10n.text("解绑设备"), role: .destructive) {
                    model.deactivate(device.deviceID)
                    deviceToDeactivate = nil
                }
            }
            Button(L10n.text("取消"), role: .cancel) { deviceToDeactivate = nil }
        } message: { Text(L10n.text("解绑释放设备名额。其它设备的已有离线凭据将在其期限结束后失效。")) }
    }
}
