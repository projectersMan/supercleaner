/// A held read for the packaged responsiveness self-check. No filesystem or
/// application operations are performed by this fixture.
actor ApplicationRefreshFixture {
    private(set) var calls = 0
    private var started: [CheckedContinuation<Void, Never>] = []
    private var pending: CheckedContinuation<Set<String>, Never>?
    func identifiers() async -> Set<String> {
        calls += 1
        let waiting = started; started.removeAll()
        waiting.forEach { $0.resume() }
        return await withCheckedContinuation { pending = $0 }
    }
    func waitUntilStarted() async {
        if calls > 0 { return }
        await withCheckedContinuation { started.append($0) }
    }
    func release() {
        pending?.resume(returning: ["org.example.running"])
        pending = nil
    }
}
