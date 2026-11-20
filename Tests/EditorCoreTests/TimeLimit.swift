import Foundation

/// A time limit for a speed test that gives way when the machine is busy.
///
/// `seconds` is what the work may take on an idle machine. The limit grows
/// with the load average per core (ten cores all busy double it), so other
/// work on the machine doesn't fail the test, while a real slowdown of the
/// code still does. A shared CI runner is slower hardware besides, so there
/// the limit never goes under `onCI`.
struct TimeLimit: CustomStringConvertible {
    let seconds: TimeInterval
    let load: Double
    let cores: Int

    init(_ idle: TimeInterval, onCI: TimeInterval? = nil) {
        var averages = [Double](repeating: 0, count: 1)
        load = getloadavg(&averages, 1) == 1 ? averages[0] : 0
        cores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let scaled = idle * (1 + load / Double(cores))
        let isCI = ProcessInfo.processInfo.environment["CI"] != nil
        seconds = isCI ? max(scaled, onCI ?? scaled) : scaled
    }

    var description: String {
        String(format: "limit %.1f s at load %.1f on %d cores", seconds, load, cores)
    }
}
