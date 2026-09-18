import Foundation
import DiskGCCore

struct ScanOutcome {
    var free: Int64
    var target: Int64
    var warn: Int64
    var candidates: [Candidate]
    var errors: [String]
    var at: Date

    var auto: [Candidate] { candidates.filter { $0.tier == .auto } }
    var ask: [Candidate] { candidates.filter { $0.tier == .ask } }
}

struct ActionOutcome {
    var results: [ExecutionResult]
    var free: Int64
    var freed: Int64
}

final class Engine {
    private let queue = DispatchQueue(label: "dev.rpo.diskgc.engine", qos: .utility)
    private let notifier: Notifier

    init(notifier: Notifier) {
        self.notifier = notifier
    }

    func scan(completion: @escaping (Result<ScanOutcome, Error>) -> Void) {
        serially(completion) {
            let runtime = try Runtime()
            let probe = runtime.sizeProbe(rescan: false)
            let scanned = ScannerRegistry.scan(runtime.context(sizes: probe))
            try runtime.save(runtime.state, sizes: probe)
            return ScanOutcome(
                free: try runtime.freeBytes(), target: runtime.targetBytes, warn: Self.warnBytes(runtime),
                candidates: scanned.candidates, errors: scanned.errors, at: Date()
            )
        }
    }

    func tick(completion: @escaping (Result<ScanOutcome, Error>) -> Void) {
        serially(completion) {
            let runtime = try Runtime()
            let probe = runtime.sizeProbe(rescan: false)
            let tick = Tick(
                ctx: runtime.context(sizes: probe), executor: runtime.executor(dryRun: false),
                notifier: self.notifier, freeBytes: runtime.freeBytes
            )
            let report = try tick.run()
            try runtime.save(report.state, sizes: probe)
            let reclaimed = Set(report.executed.filter(\.ok).map(\.candidate.id))
            return ScanOutcome(
                free: report.freeAfter, target: report.target, warn: Self.warnBytes(runtime),
                candidates: report.candidates.filter { !reclaimed.contains($0.id) }, errors: report.errors, at: Date()
            )
        }
    }

    func execute(_ candidates: [Candidate], completion: @escaping (Result<ActionOutcome, Error>) -> Void) {
        serially(completion) {
            let runtime = try Runtime()
            let executor = runtime.executor(dryRun: false)
            let before = try runtime.freeBytes()
            let results = candidates.map { executor.execute($0) }
            let after = try runtime.freeBytes()
            return ActionOutcome(results: results, free: after, freed: max(0, after - before))
        }
    }

    func keep(worktree path: String, completion: @escaping (Result<Void, Error>) -> Void) {
        serially(completion) {
            let runtime = try Runtime()
            var state = runtime.state
            guard !state.keptWorktrees.contains(path) else { return }
            state.keptWorktrees.append(path)
            try state.save(to: runtime.statePath)
        }
    }

    static func warnBytes(_ runtime: Runtime) -> Int64 {
        Int64(runtime.config.warnFreeGB) * ByteFormat.gigabyte
    }

    private func serially<T>(_ completion: @escaping (Result<T, Error>) -> Void, _ work: @escaping () throws -> T) {
        queue.async {
            let outcome = Result { try work() }
            DispatchQueue.main.async { completion(outcome) }
        }
    }
}
