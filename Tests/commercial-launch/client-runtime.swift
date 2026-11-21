import CleanerCore
import CryptoKit
import Foundation

private struct ClientCheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class ClientMemoryStorage: CommercialCredentialStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data
    init(state: CommercialCredentialState) throws { data = try JSONEncoder().encode(state) }
    func read() throws -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func write(_ data: Data) throws { lock.lock(); defer { lock.unlock() }; self.data = data }
    func state() throws -> CommercialCredentialState { try JSONDecoder().decode(CommercialCredentialState.self, from: read()!) }
}

private final class ClientCheckClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func set(_ date: Date) { lock.lock(); defer { lock.unlock() }; self.date = date }
}

private enum ClientReply: Sendable {
    case json(Int, Data)
    case failure(URLError)
    case delayed(String, Int, Data)
}

private struct ClientStep: Sendable { let path: String; let reply: ClientReply }

private final class ClientHTTPQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [ClientStep] = []
    private var pending: [String: (ClientHTTPProtocol, ClientReply)] = [:]
    private var requestedPaths: [String] = []

    func set(_ steps: [ClientStep]) { lock.lock(); defer { lock.unlock() }; self.steps = steps; requestedPaths = [] }
    func next(_ request: URLRequest, connection: ClientHTTPProtocol) -> ClientReply? {
        lock.lock(); defer { lock.unlock() }
        guard let url = request.url, !steps.isEmpty else { return .failure(URLError(.resourceUnavailable)) }
        requestedPaths.append(url.path)
        let step = steps.removeFirst()
        guard url.path == step.path, request.httpMethod == "POST", url.scheme == "https" else { return .failure(URLError(.badURL)) }
        if case let .delayed(id, status, body) = step.reply {
            pending[id] = (connection, .json(status, body))
            return nil
        }
        return step.reply
    }
    func isPending(_ id: String) -> Bool { lock.lock(); defer { lock.unlock() }; return pending[id] != nil }
    func release(_ id: String) {
        lock.lock()
        let entry = pending.removeValue(forKey: id)!
        lock.unlock()
        entry.0.deliver(entry.1)
    }
    func cancel(_ connection: ClientHTTPProtocol) {
        lock.lock(); defer { lock.unlock() }
        for id in Array(pending.keys) where pending[id]!.0 === connection { pending.removeValue(forKey: id) }
    }
    func requestCount() -> Int { lock.lock(); defer { lock.unlock() }; return requestedPaths.count }
    func waitForPending(_ id: String) async throws {
        for _ in 0..<1_000 {
            if isPending(id) { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw ClientCheckFailure(message: "Timed out waiting for the controlled refresh request")
    }
}

private final class ClientHTTPProtocol: URLProtocol, @unchecked Sendable {
    static let queue = ClientHTTPQueue()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let reply = Self.queue.next(request, connection: self) { deliver(reply) }
    }
    override func stopLoading() { Self.queue.cancel(self) }
    func deliver(_ reply: ClientReply) {
        switch reply {
        case let .json(status, body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error): client?.urlProtocol(self, didFailWithError: error)
        case .delayed: preconditionFailure("Delayed replies must be released by the queue")
        }
    }
}

private struct ClientIdentity {
    let key = Curve25519.Signing.PrivateKey()
    let deviceID = UUID()
    let productID = "supercleaner-client-check"
    let email = "buyer@supercleaner.dev"
    let now = Int64(Date().timeIntervalSince1970)

    func configuration() throws -> CommercialConfiguration {
        try CommercialConfiguration(data: JSONSerialization.data(withJSONObject: ["schemaVersion": 1,
            "productID": productID, "apiBaseURL": "https://commerce.supercleaner.dev",
            "licensePublicKey": key.publicKey.rawRepresentation.base64EncodedString()]))
    }
    func license(email: String, issuedOffset: Int64, validOffset: Int64) throws -> SignedLicense {
        let claims = LicenseClaims(licenseID: UUID(), productID: productID, email: email, deviceID: deviceID,
            issuedAt: now + issuedOffset, offlineValidUntil: now + validOffset, capabilities: [.standardScan, .agentScan, .newCleanup])
        let data = try JSONEncoder().encode(claims)
        return SignedLicense(claimsData: data, signature: try key.signature(for: data))
    }
    func storage(signed: SignedLicense?) throws -> ClientMemoryStorage {
        try ClientMemoryStorage(state: CommercialCredentialState(deviceID: deviceID,
            email: signed == nil ? nil : email, licenseKey: signed == nil ? nil : "first-license",
            signedLicense: signed, lastTrustedTime: nil, pendingOrder: nil))
    }
    func access(storage: ClientMemoryStorage, now: @escaping @Sendable () -> Date = Date.init) throws -> CommercialAccess {
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [ClientHTTPProtocol.self]
        return CommercialAccess(configuration: .success(try configuration()), storage: storage, sessionConfiguration: session, now: now)
    }
}

@main private enum ClientRuntimeCheck {
    static func main() async {
        let result = await Task { try await run() }.result
        switch result {
        case .success: print("PASS: commercial client URLSession runtime checks")
        case let .failure(error):
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        if CommandLine.arguments.contains("--automatic-renewal-only") { try await checkAutomaticRenewal(); return }
        if CommandLine.arguments.contains("--device-transfer-only") { try await checkDeviceTransferWithoutSlot(); return }
        if CommandLine.arguments.contains("--polling-cancellation-only") { try await checkPollingCancellation(); return }
        if CommandLine.arguments.contains("--expired-observation-only") { try await checkExpiredObservation(); return }
        try await checkPaymentAndRecovery()
        try await checkPollingCancellation()
        try await checkDeviceTransferWithoutSlot()
        try await checkRefreshRace()
        try await checkAutomaticRenewal()
        try await checkOfflineRenewalAndRevocation()
        try await checkExpiredObservation()
    }

    static func checkPaymentAndRecovery() async throws {
        let identity = ClientIdentity()
        let storage = try identity.storage(signed: nil)
        let access = try identity.access(storage: storage)
        let order = ["orderID": UUID().uuidString, "pollToken": String(repeating: "s", count: 43),
            "checkoutURL": "https://commerce.supercleaner.dev/checkout/purchase?token=opaque"]
        let signed = try identity.license(email: identity.email, issuedOffset: -1, validOffset: 3_600)
        ClientHTTPProtocol.queue.set([
            ClientStep(path: "/v1/orders", reply: .json(200, try JSONEncoder().encode(order))),
            ClientStep(path: "/v1/orders/status", reply: .json(200, Data("{\"status\":\"paid\",\"licenseKey\":\"first-license\"}".utf8))),
            ClientStep(path: "/v1/licenses/activate", reply: .json(200, try JSONEncoder().encode(signed)))])
        _ = try await access.purchase(email: identity.email)
        guard try storage.state().pendingOrder != nil else { throw ClientCheckFailure(message: "Pending purchase was not persisted before opening checkout") }
        guard try await access.checkPayment(deviceName: "Test Mac") else { throw ClientCheckFailure(message: "Paid order did not activate") }
        guard try await access.activationCodeForCopy() == "first-license", try storage.state().completedOrder != nil else {
            throw ClientCheckFailure(message: "Paid purchase credentials cannot be recovered for the second Mac")
        }
        try await access.require(.newCleanup)
        ClientHTTPProtocol.queue.set([ClientStep(path: "/v1/licenses/refresh", reply: .failure(URLError(.notConnectedToInternet)))])
        let disconnected = await Task { try await access.refresh(deviceName: "Test Mac") }.result
        guard case .failure = disconnected else { throw ClientCheckFailure(message: "Disconnected refresh unexpectedly succeeded") }
        try await access.require(.newCleanup)
        ClientHTTPProtocol.queue.set([ClientStep(path: "/v1/licenses/refresh", reply: .json(500, Data("{\"error\":\"temporarily unavailable\"}".utf8)))])
        let unavailable = await Task { try await access.refresh(deviceName: "Test Mac") }.result
        guard case .failure = unavailable else { throw ClientCheckFailure(message: "Server failure unexpectedly succeeded") }
        try await access.require(.newCleanup)
        ClientHTTPProtocol.queue.set([ClientStep(path: "/v1/licenses/activate", reply: .json(403, Data("{\"error\":\"invalid alternate license\"}".utf8)))])
        let badActivation = await Task { try await access.activate(email: identity.email, licenseKey: "wrong-license", deviceName: "Test Mac") }.result
        guard case .failure = badActivation else { throw ClientCheckFailure(message: "Invalid activation unexpectedly succeeded") }
        try await access.require(.newCleanup)
        ClientHTTPProtocol.queue.set([ClientStep(path: "/v1/licenses/refresh", reply: .json(200, Data(repeating: 0x20, count: 65_537)))])
        let oversized = await Task { try await access.refresh(deviceName: "Test Mac") }.result
        guard case .failure = oversized else { throw ClientCheckFailure(message: "Oversized streaming response was accepted") }
        try await access.require(.newCleanup)
        let otherID = UUID()
        let deviceData = try JSONSerialization.data(withJSONObject: ["devices": [["deviceID": identity.deviceID.uuidString,
            "deviceName": "Test Mac", "activatedAt": identity.now], ["deviceID": otherID.uuidString,
            "deviceName": "Other Mac", "activatedAt": identity.now]]])
        ClientHTTPProtocol.queue.set([
            ClientStep(path: "/v1/licenses/devices", reply: .json(200, deviceData)),
            ClientStep(path: "/v1/licenses/deactivate", reply: .json(200, Data("{\"deactivated\":true}".utf8))),
            ClientStep(path: "/v1/licenses/deactivate", reply: .json(200, Data("{\"deactivated\":true}".utf8))),
            ClientStep(path: "/v1/licenses/activate", reply: .json(200, try JSONEncoder().encode(signed)))])
        guard try await access.devices().count == 2 else { throw ClientCheckFailure(message: "Device list was not decoded") }
        try await access.deactivate(otherID)
        try await access.require(.newCleanup)
        try await access.deactivate(identity.deviceID)
        let unbound = await Task { try await access.require(.newCleanup) }.result
        guard case .failure = unbound else { throw ClientCheckFailure(message: "Local deactivation retained paid authorization") }
        try await access.activate(email: identity.email, licenseKey: "first-license", deviceName: "Test Mac")
        ClientHTTPProtocol.queue.set([ClientStep(path: "/v1/licenses/refresh", reply: .json(403, Data("{\"error\":\"revoked\"}".utf8)))])
        let revoked = await Task { try await access.refresh(deviceName: "Test Mac") }.result
        guard case .failure = revoked, try storage.state().signedLicense == nil,
              try storage.state().licenseKey == "first-license" else { throw ClientCheckFailure(message: "Definitive revocation did not clear only the signed lease") }
        let denied = await Task { try await access.require(.newCleanup) }.result
        guard case .failure = denied else { throw ClientCheckFailure(message: "Revoked lease still authorized cleanup") }
        try await access.require(.restore)
        print("PASS: payment to activation, persisted recovery and second-device code, network/5xx retention, invalid activation retention, bounded streaming, device list/local and remote deactivation, revocation and safe restore")
    }

    @MainActor static func checkPollingCancellation() async throws {
        let identity = ClientIdentity()
        let storage = try identity.storage(signed: nil)
        var state = try storage.state()
        state.pendingOrder = CommercialPendingOrder(orderID: UUID().uuidString, pollToken: String(repeating: "p", count: 43), email: identity.email)
        try storage.write(JSONEncoder().encode(state))
        let access = try identity.access(storage: storage)
        ClientHTTPProtocol.queue.set([ClientStep(path: "/v1/orders/status", reply: .delayed("cancel-poll", 200, Data("{\"status\":\"pending\",\"licenseKey\":null}".utf8)))])
        let model = CommercialSettingsModel(access: access)
        model.checkPayment()
        try await ClientHTTPProtocol.queue.waitForPending("cancel-poll")
        model.stopPolling()
        for _ in 0..<1_000 {
            if !model.isPolling { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        guard !model.isPolling, model.error == nil, ClientHTTPProtocol.queue.requestCount() == 1,
              !ClientHTTPProtocol.queue.isPending("cancel-poll"), try storage.state().pendingOrder != nil else {
            throw ClientCheckFailure(message: "Stop Checking must cancel the actual HTTP polling task and retain purchase recovery")
        }
        print("PASS: stopping payment polling cancels the real HTTP task and preserves order recovery")
    }

    static func checkDeviceTransferWithoutSlot() async throws {
        let identity = ClientIdentity()
        let storage = try identity.storage(signed: nil)
        let access = try identity.access(storage: storage)
        let otherID = UUID()
        let deviceData = try JSONSerialization.data(withJSONObject: ["devices": [["deviceID": otherID.uuidString,
            "deviceName": "Old Mac", "activatedAt": identity.now]]])
        let signed = try identity.license(email: identity.email, issuedOffset: -1, validOffset: 3_600)
        ClientHTTPProtocol.queue.set([
            ClientStep(path: "/v1/licenses/activate", reply: .json(409, Data("{\"error\":\"device limit reached\"}".utf8))),
            ClientStep(path: "/v1/licenses/devices", reply: .json(200, deviceData)),
            ClientStep(path: "/v1/licenses/deactivate", reply: .json(200, Data("{\"deactivated\":true}".utf8))),
            ClientStep(path: "/v1/licenses/activate", reply: .json(200, try JSONEncoder().encode(signed)))])
        let full = await Task { try await access.activate(email: identity.email, licenseKey: "first-license", deviceName: "New Mac") }.result
        guard case .failure = full else { throw ClientCheckFailure(message: "The controlled device-limit failure did not reach the user") }
        let devices = try await access.devices()
        guard devices.count == 1, devices[0].deviceID == otherID, try storage.state().signedLicense == nil else {
            throw ClientCheckFailure(message: "A new Mac must manage old devices without gaining a paid authorization first")
        }
        try await access.deactivate(otherID)
        try await access.activate(email: identity.email, licenseKey: "first-license", deviceName: "New Mac")
        try await access.require(.newCleanup)
        print("PASS: a new Mac can release an old device slot after an explicit 409 and then activate without any bypass")
    }

    static func checkRefreshRace() async throws {
        let identity = ClientIdentity()
        let initial = try identity.license(email: identity.email, issuedOffset: -1, validOffset: 3_600)
        let storage = try identity.storage(signed: initial)
        let access = try identity.access(storage: storage)
        let alternate = try identity.license(email: "second@supercleaner.dev", issuedOffset: -1, validOffset: 3_600)
        ClientHTTPProtocol.queue.set([
            ClientStep(path: "/v1/licenses/refresh", reply: .delayed("old-refresh", 403, Data("{\"error\":\"old license revoked\"}".utf8))),
            ClientStep(path: "/v1/licenses/activate", reply: .json(200, try JSONEncoder().encode(alternate)))])
        let refresh = Task { try await access.refresh(deviceName: "Test Mac") }
        try await ClientHTTPProtocol.queue.waitForPending("old-refresh")
        try await access.activate(email: "second@supercleaner.dev", licenseKey: "second-license", deviceName: "Test Mac")
        ClientHTTPProtocol.queue.release("old-refresh")
        let stale = await refresh.result
        guard case .failure = stale, try storage.state().signedLicense == alternate,
              try await access.activationCodeForCopy() == "second-license" else { throw ClientCheckFailure(message: "Stale refresh 403 erased the newly activated license") }
        try await access.require(.newCleanup)
        print("PASS: delayed old-license refresh 403 cannot erase a newly activated license")
    }

    static func checkOfflineRenewalAndRevocation() async throws {
        let identity = ClientIdentity()
        let due = try identity.license(email: identity.email, issuedOffset: -3_600, validOffset: 120)
        let storage = try identity.storage(signed: due)
        let access = try identity.access(storage: storage)
        ClientHTTPProtocol.queue.set([ClientStep(path: "/v1/licenses/refresh", reply: .failure(URLError(.notConnectedToInternet)))])
        let observed = Date()
        let failed = await Task { try await access.refreshIfNeeded() }.result
        guard case .failure = failed, let trusted = try storage.state().lastTrustedTime, trusted >= observed else {
            throw ClientCheckFailure(message: "Background renewal failure must retain its observed clock baseline")
        }
        try await access.require(.standardScan)
        let throttled = await Task { try await access.refreshIfNeeded() }.result
        guard case .failure = throttled, ClientHTTPProtocol.queue.requestCount() == 1,
              try storage.state().signedLicense == due else { throw ClientCheckFailure(message: "Automatic retry was not throttled or valid offline credentials were removed") }
        let revokedStorage = try identity.storage(signed: due)
        let revokedAccess = try identity.access(storage: revokedStorage)
        ClientHTTPProtocol.queue.set([ClientStep(path: "/v1/licenses/refresh", reply: .json(403, Data("{\"error\":\"revoked\"}".utf8)))])
        let revoked = await Task { try await revokedAccess.refreshIfNeeded() }.result
        guard case .failure = revoked else { throw ClientCheckFailure(message: "Expected definitive revocation failure") }
        let denied = await Task { try await revokedAccess.require(.newCleanup) }.result
        guard case .failure = denied, try revokedStorage.state().signedLicense == nil else {
            throw ClientCheckFailure(message: "A background 403 must immediately deny cleanup even within the offline lease")
        }
        print("PASS: due background renewal preserves valid offline access on disconnect, throttles retries, and immediately honors definitive revocation")
    }

    static func checkExpiredObservation() async throws {
        let identity = ClientIdentity()
        let expired = try identity.license(email: identity.email, issuedOffset: -20, validOffset: -10)
        let storage = try identity.storage(signed: expired)
        let observed = Date(timeIntervalSince1970: TimeInterval(identity.now))
        let clock = ClientCheckClock(observed)
        let access = try identity.access(storage: storage, now: clock.read)
        ClientHTTPProtocol.queue.set([ClientStep(path: "/v1/licenses/refresh", reply: .failure(URLError(.notConnectedToInternet)))])
        let denied = await Task { try await access.require(.newCleanup) }.result
        guard case .failure = denied, let trusted = try storage.state().lastTrustedTime, trusted >= observed else {
            throw ClientCheckFailure(message: "An expired lease rejection must persist the observed time even when online renewal fails")
        }
        clock.set(observed.addingTimeInterval(-15))
        let rollback = await Task { try await access.require(.newCleanup) }.result
        guard case let .failure(rollbackError) = rollback, rollbackError as? LicenseAuthorizationError == .clockRollback else {
            throw ClientCheckFailure(message: "Rolling back into an old lease after seeing expiry must remain denied")
        }
        let future = observed.addingTimeInterval(10_000_000)
        clock.set(future)
        let ahead = await Task { try await access.require(.newCleanup) }.result
        guard case .failure = ahead, try storage.state().lastTrustedTime == future else {
            throw ClientCheckFailure(message: "A rejected future observation must be recorded before any failed or throttled renewal")
        }
        try await access.require(.restore)
        clock.set(observed)
        let reopened = try identity.access(storage: storage, now: clock.read)
        let cached = await Task { try await reopened.require(.standardScan) }.result
        guard case let .failure(cachedError) = cached, cachedError as? LicenseAuthorizationError == .clockRollback else {
            throw ClientCheckFailure(message: "Cached credentials must retain the previous observation baseline")
        }
        let renewed = try identity.license(email: identity.email, issuedOffset: -1, validOffset: 3_600)
        ClientHTTPProtocol.queue.set([ClientStep(path: "/v1/licenses/refresh", reply: .json(200, try JSONEncoder().encode(renewed)))])
        try await reopened.refresh(deviceName: "Corrected Clock Mac")
        guard try storage.state().lastTrustedTime == observed.addingTimeInterval(-1) else {
            throw ClientCheckFailure(message: "A verified fresh server lease must establish a signed server-time baseline")
        }
        try await reopened.require(.newCleanup)
        print("PASS: failed expiry persists observed time, clock rollback stays denied, safety rights remain, and a fresh HTTPS-signed lease recovers after clock calibration")
    }

    static func checkAutomaticRenewal() async throws {
        let identity = ClientIdentity()
        let expired = try identity.license(email: identity.email, issuedOffset: -20, validOffset: -10)
        let renewed = try identity.license(email: identity.email, issuedOffset: -1, validOffset: 3_600)
        let storage = try identity.storage(signed: expired)
        let access = try identity.access(storage: storage)
        ClientHTTPProtocol.queue.set([ClientStep(path: "/v1/licenses/refresh", reply: .delayed("automatic-renewal", 200, try JSONEncoder().encode(renewed)))])
        let first = Task { try await access.require(.newCleanup) }
        try await ClientHTTPProtocol.queue.waitForPending("automatic-renewal")
        let second = Task { try await access.require(.standardScan) }
        await Task.yield()
        ClientHTTPProtocol.queue.release("automatic-renewal")
        try await first.value
        try await second.value
        guard try storage.state().signedLicense == renewed, ClientHTTPProtocol.queue.requestCount() == 1 else {
            throw ClientCheckFailure(message: "Expired offline lease was not renewed exactly once before authorization")
        }
        try await access.require(.standardScan)
        guard ClientHTTPProtocol.queue.requestCount() == 1 else { throw ClientCheckFailure(message: "Fresh credentials triggered another network request") }
        print("PASS: expired concurrent authorization shares one renewal and fresh authorization stays offline")
    }
}
