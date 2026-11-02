import Foundation

let MACFFMTrustProbeArgument = "--accessibility-probe"
let MACTranslatorScreenProbeArgument = "--screen-recording-probe"
let MACTranslatorReaderArgument = "--read-text"

enum HelperTrustProbePolicy {
    enum WaitResult: Equatable, Sendable {
        case running
        case interrupted
        case exited(Int32)
        case signaled
        case failed
    }

    struct Operations {
        var executablePath: () -> String?
        var spawn: (String) -> Int32?
        var wait: (Int32) -> WaitResult
        var kill: (Int32) -> Void
        var reap: (Int32) -> WaitResult
        var sleep: () -> Void
        var fallback: () -> Bool
    }

    static func childExitStatus(trustBit: () -> Bool) -> Int32 {
        trustBit() ? 0 : 1
    }

    static func isTrusted(_ operations: Operations) -> Bool {
        finish(spawn(operations), operations)
    }

    static func spawn(_ operations: Operations) -> Int32? {
        operations.executablePath().flatMap(operations.spawn)
    }

    static func finish(_ child: Int32?, _ operations: Operations) -> Bool {
        guard let child else { return operations.fallback() }
        for _ in 0..<100 {
            switch operations.wait(child) {
            case .exited(let status):
                return status == 0
            case .signaled:
                return operations.fallback()
            case .failed:
                return cleanUp(child, operations)
            case .running, .interrupted:
                operations.sleep()
            }
        }
        return cleanUp(child, operations)
    }

    private static func cleanUp(_ child: Int32, _ operations: Operations) -> Bool {
        operations.kill(child)
        while operations.reap(child) == .interrupted {}
        return operations.fallback()
    }
}
