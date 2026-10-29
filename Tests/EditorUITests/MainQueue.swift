import XCTest

extension XCTestCase {
    /// Runs everything queued on the main queue, including what those
    /// blocks queue in turn (a few hops deep). A fixed `RunLoop.run(until:)`
    /// sometimes returns before the queue is serviced.
    @MainActor
    func drainMainQueue(hops: Int = 4) {
        for _ in 0..<hops {
            let drained = expectation(description: "main queue drained")
            DispatchQueue.main.async { drained.fulfill() }
            wait(for: [drained], timeout: 2)
        }
    }
}
