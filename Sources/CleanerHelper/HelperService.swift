import CleanerCore
import Foundation

final class HelperService: NSObject, CleanerHelperXPCProtocol, @unchecked Sendable {
    private let handler: HelperRequestHandler
    private let scope: HelperFileScope
    init(handler: HelperRequestHandler, scope: HelperFileScope) { self.handler = handler; self.scope = scope }
    func ping(withReply reply: @escaping @Sendable (Int) -> Void) { reply(2) }
    func perform(requestData: Data, withReply reply: @escaping @Sendable (Data) -> Void) {
        Task {
            let response = await handler.handle(requestData, scope: scope)
            reply((try? JSONEncoder().encode(response)) ?? Data())
        }
    }
}
