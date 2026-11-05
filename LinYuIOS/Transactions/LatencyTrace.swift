import Foundation

/// Monotonic intervals. Callers use fixed stage names and outcomes, never response contents.
@MainActor final class LatencyTrace {
    private let operation: String
    private let start = DispatchTime.now().uptimeNanoseconds
    private var previous: UInt64?
    private var events: [String] = []
    private let report: (String) -> Void
    var onStage: ((String) -> Void)?

    init(_ operation: String, report: @escaping (String) -> Void) {
        self.operation = operation
        self.report = report
    }

    func mark(_ stage: String) {
        let now = DispatchTime.now().uptimeNanoseconds
        let total = (now - start) / 1_000_000
        let interval = (now - (previous ?? start)) / 1_000_000
        previous = now
        events.append("\(stage)=\(total)ms(+\(interval))")
        onStage?(stage)
    }

    func finish(_ outcome: String) {
        mark(outcome)
        report("LATENCY \(operation) " + events.joined(separator: " "))
    }
}
