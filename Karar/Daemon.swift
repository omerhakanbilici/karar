import Foundation
import Observation

/// Owns the connection to the Ollaya daemon: adopts one that is already running,
/// or starts the bundled binary and stops it again on quit.
@MainActor @Observable
final class Daemon {
    enum State: Equatable {
        case starting
        case running(owned: Bool)
        case portInUse         // something that is not Ollaya answers on 11435 (spec §5)
        case failed(String)

        var isRunning: Bool {
            if case .running = self { true } else { false }
        }
    }

    typealias Probe = @MainActor () async -> Liveness
    typealias Launch = @MainActor (_ onExit: @escaping @Sendable (Int32) -> Void) throws -> @MainActor () -> Void

    private(set) var state: State = .starting

    private let probe: Probe
    private let launch: Launch
    private let readyTimeout: Duration
    private var terminate: (@MainActor () -> Void)?
    private var restarts = 0
    private var starting = false

    init(probe: @escaping Probe, launch: @escaping Launch, readyTimeout: Duration = .seconds(10)) {
        self.probe = probe
        self.launch = launch
        self.readyTimeout = readyTimeout
    }

    func start() async {
        guard !starting, terminate == nil else { return }
        starting = true
        defer { starting = false }
        restarts = 0
        state = .starting
        switch await probe() {
        case .ollaya: state = .running(owned: false)
        case .other: state = .portInUse
        case .none: await launchAndWait()
        }
    }

    func stop() {
        let terminate = self.terminate
        self.terminate = nil   // cleared first so the exit it causes is ignored
        terminate?()
    }

    private func launchAndWait() async {
        state = .starting
        do {
            terminate = try launch { [weak self] status in
                Task { @MainActor in self?.processExited(status) }
            }
        } catch {
            state = .failed("Could not start Ollaya: \(error.localizedDescription)")
            return
        }
        let deadline = ContinuousClock.now + readyTimeout
        while ContinuousClock.now < deadline {
            if terminate == nil { return }   // exited during startup; processExited set the state
            if await probe() == .ollaya {
                if terminate == nil { return }   // exited while the probe was in flight; keep .failed
                state = .running(owned: true)
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        stop()
        state = .failed("Ollaya did not start within \(Int(readyTimeout.components.seconds)) seconds.")
    }

    private func processExited(_ status: Int32) {
        guard terminate != nil else { return }   // stopped on purpose
        terminate = nil
        if case .running = state, restarts == 0 {
            restarts += 1
            Task { await launchAndWait() }
        } else {
            state = .failed("Ollaya stopped unexpectedly (exit code \(status)).")
        }
    }
}

extension Daemon {
    /// The pinned Ollaya version inside the app ("v0.5.0"), copied from vendor/ollaya/VERSION.
    nonisolated static let bundledVersion: String =
        Bundle.main.url(forResource: "VERSION", withExtension: nil, subdirectory: "Ollaya")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    /// Where a daemon Karar starts writes its output.
    nonisolated static let logURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appending(path: "Logs/Karar/ollaya.log")

    /// Keeps the log bounded: past `limit` bytes it becomes `<name>.1`, replacing an older one.
    nonisolated static func rotateLog(at url: URL, limit: Int) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size > limit else { return }
        let old = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
    }

    /// Starts `Contents/MacOS/ollaya serve`, logging to `logURL` (~/Library/Logs/Karar/ollaya.log).
    // ponytail: if Karar crashes the daemon is orphaned; the next launch adopts it and never stops it.
    static func bundledLaunch(onExit: @escaping @Sendable (Int32) -> Void) throws -> @MainActor () -> Void {
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "ollaya") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let logURL = logURL
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        rotateLog(at: logURL, limit: 10_000_000)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let log = try FileHandle(forWritingTo: logURL)
        try log.seekToEnd()   // append across launches/restarts instead of truncating

        let process = Process()
        process.executableURL = executable
        process.arguments = ["serve"]
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { onExit($0.terminationStatus) }
        try process.run()
        return {
            process.terminate()
            // Bounded wait: ~3 s for a graceful exit before we force it, so a SIGTERM-ignoring
            // ollaya can't hang the main actor forever (during the timeout path or on quit).
            for _ in 0..<60 where process.isRunning {
                usleep(50_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
        }
    }
}
