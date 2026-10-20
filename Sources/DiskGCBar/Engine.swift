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
    private let scanQueue = DispatchQueue(label: "dev.rpo.diskgc.scan", qos: .utility)
    private let actionQueue = DispatchQueue(label: "dev.rpo.diskgc.action", qos: .userInitiated)
    private let notifier: Notifier

    init(notifier: Notifier) {
        self.notifier = notifier
    }

    func restore(completion: @escaping (Result<ScanOutcome?, Error>) -> Void) {
        run(on: actionQueue, completion) {
            let runtime = try Runtime()
            guard let snapshot = ScanSnapshot.load(from: runtime.lastScanPath) else { return nil }
            return ScanOutcome(
                free: try runtime.freeBytes(), target: runtime.targetBytes, warn: Self.warnBytes(runtime),
                candidates: snapshot.candidates, errors: snapshot.errors, at: snapshot.at
            )
        }
    }

    func scan(completion: @escaping (Result<ScanOutcome, Error>) -> Void) {
        run(on: scanQueue, completion) {
            let runtime = try Runtime()
            let probe = runtime.sizeProbe(rescan: false)
            let scanned = ScannerRegistry.scan(runtime.context(sizes: probe))
            try runtime.save(runtime.state, sizes: probe)
            let outcome = ScanOutcome(
                free: try runtime.freeBytes(), target: runtime.targetBytes, warn: Self.warnBytes(runtime),
                candidates: scanned.candidates, errors: scanned.errors, at: Date()
            )
            try Self.remember(outcome, runtime)
            return outcome
        }
    }

    func tick(completion: @escaping (Result<ScanOutcome, Error>) -> Void) {
        run(on: scanQueue, completion) {
            let runtime = try Runtime()
            let probe = runtime.sizeProbe(rescan: false)
            let tick = Tick(
                ctx: runtime.context(sizes: probe), executor: runtime.executor(dryRun: false),
                notifier: self.notifier, freeBytes: runtime.freeBytes
            )
            let report = try tick.run()
            try runtime.save(report.state, sizes: probe)
            let reclaimed = Set(report.executed.filter(\.ok).map(\.candidate.id))
            let outcome = ScanOutcome(
                free: report.freeAfter, target: report.target, warn: Self.warnBytes(runtime),
                candidates: report.candidates.filter { !reclaimed.contains($0.id) }, errors: report.errors, at: Date()
            )
            try Self.remember(outcome, runtime)
            return outcome
        }
    }

    func execute(_ candidates: [Candidate], completion: @escaping (Result<ActionOutcome, Error>) -> Void) {
        run(on: actionQueue, completion) {
            let runtime = try Runtime()
            let executor = runtime.executor(dryRun: false)
            let before = try runtime.freeBytes()
            let results = candidates.map { executor.execute($0) }
            let after = try runtime.freeBytes()
            return ActionOutcome(results: results, free: after, freed: max(0, after - before))
        }
    }

    func forget(_ ids: Set<String>) {
        run(on: scanQueue, { _ in }) {
            let runtime = try Runtime()
            try ScanSnapshot.forget(ids, at: runtime.lastScanPath)
        }
    }

    func keep(worktree path: String, completion: @escaping (Result<Void, Error>) -> Void) {
        run(on: scanQueue, completion) {
            let runtime = try Runtime()
            try ScanSnapshot.forget([path], at: runtime.lastScanPath)
            var state = runtime.state
            guard !state.keptWorktrees.contains(path) else { return }
            state.keptWorktrees.append(path)
            try state.save(to: runtime.statePath)
        }
    }

    static func warnBytes(_ runtime: Runtime) -> Int64 {
        Int64(runtime.config.warnFreeGB) * ByteFormat.gigabyte
    }

    private static func remember(_ outcome: ScanOutcome, _ runtime: Runtime) throws {
        try ScanSnapshot(at: outcome.at, candidates: outcome.candidates, errors: outcome.errors).save(to: runtime.lastScanPath)
    }

    private func run<T>(on queue: DispatchQueue, _ completion: @escaping (Result<T, Error>) -> Void, _ work: @escaping () throws -> T) {
        queue.async {
            let outcome = Result { try work() }
            DispatchQueue.main.async { completion(outcome) }
        }
    }
}
