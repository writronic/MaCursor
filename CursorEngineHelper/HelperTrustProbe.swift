@preconcurrency import ApplicationServices
import Darwin
import Foundation

@MainActor
enum HelperTrustProbe {
    static func childMain() -> Int32 {
        HelperTrustProbePolicy.childExitStatus(trustBit: inProcessTrustBit)
    }

    static func isTrusted() -> Bool {
        HelperTrustProbePolicy.isTrusted(.init(
            executablePath: { Bundle.main.executablePath },
            spawn: spawn,
            wait: { wait($0, options: WNOHANG) },
            kill: { _ = Darwin.kill($0, SIGKILL) },
            reap: { wait($0, options: 0) },
            sleep: { usleep(5_000) },
            fallback: inProcessTrustBit
        ))
    }

    static func screenRecordingChildMain() -> Int32 {
        HelperTrustProbePolicy.childExitStatus(trustBit: CGPreflightScreenCaptureAccess)
    }

    static func screenRecordingAllowed() -> Bool {
        screenRecordingAllowed(spawnScreenRecordingProbe())
    }

    static func spawnScreenRecordingProbe() -> Int32? {
        HelperTrustProbePolicy.spawn(screenRecording)
    }

    static func screenRecordingAllowed(_ spawned: Int32?) -> Bool {
        HelperTrustProbePolicy.finish(spawned, screenRecording)
    }

    private static var screenRecording: HelperTrustProbePolicy.Operations {
        .init(
            executablePath: { Bundle.main.executablePath },
            spawn: { spawn($0, MACTranslatorScreenProbeArgument) },
            wait: { wait($0, options: WNOHANG) },
            kill: { _ = Darwin.kill($0, SIGKILL) },
            reap: { wait($0, options: 0) },
            sleep: { usleep(5_000) },
            fallback: CGPreflightScreenCaptureAccess
        )
    }

    private static func inProcessTrustBit() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func spawn(_ path: String) -> Int32? {
        spawn(path, MACFFMTrustProbeArgument)
    }

    private static func spawn(_ path: String, _ flag: String) -> Int32? {
        var executable = Array(path.utf8CString)
        var argument = Array(flag.utf8CString)
        return executable.withUnsafeMutableBufferPointer { executable in
            argument.withUnsafeMutableBufferPointer { argument in
                var arguments = [executable.baseAddress, argument.baseAddress, nil]
                var child: pid_t = 0
                let result = posix_spawn(&child, executable.baseAddress!, nil, nil,
                                         &arguments, _NSGetEnviron().pointee)
                return result == 0 ? child : nil
            }
        }
    }

    private static func wait(_ child: Int32, options: Int32) -> HelperTrustProbePolicy.WaitResult {
        var status: Int32 = 0
        let result = waitpid(child, &status, options)
        if result == child {
            return MACProcessDidExit(status) != 0 ? .exited(MACProcessExitStatus(status)) : .signaled
        }
        if result == 0 { return .running }
        return errno == EINTR ? .interrupted : .failed
    }
}
