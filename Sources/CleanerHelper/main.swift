import CleanerCore
import Darwin
import Foundation

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let identity: HelperSigningIdentity
    private let handler: HelperRequestHandler
    init(identity: HelperSigningIdentity) {
        self.identity = identity
        handler = HelperRequestHandler(authorizer: HelperAuthorizer(expectedCallerRequirement: identity.callerRequirement))
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier > 0,
              let scope = try? HelperFileScope.forUser(connection.effectiveUserIdentifier) else { return false }
        // Public per-message peer validation: no private auditToken, PID race or
        // client-supplied signing requirement / home directory.
        connection.setCodeSigningRequirement(identity.callerRequirement)
        connection.exportedInterface = NSXPCInterface(with: CleanerHelperXPCProtocol.self)
        connection.exportedObject = HelperService(handler: handler, scope: scope)
        connection.resume()
        return true
    }

}

do {
    let identity = try HelperSigningIdentity.current(isHelper: true)
    if CommandLine.arguments.contains("--self-check") {
        print("Helper signing identity verified; protocol 2")
        exit(0)
    }
    guard geteuid() == 0 else { exit(77) }
    let delegate = HelperListenerDelegate(identity: identity)
    let listener = NSXPCListener(machServiceName: identity.serviceName)
    listener.delegate = delegate
    listener.resume()
    withExtendedLifetime(delegate) { RunLoop.current.run() }
} catch {
    FileHandle.standardError.write(Data("Helper signing identity is unavailable.\n".utf8))
    exit(78)
}
