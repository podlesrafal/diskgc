import Foundation

public struct ReviewIO {
    public var prompt: (String) -> String?
    public var print: (String) -> Void

    public init(prompt: @escaping (String) -> String?, print: @escaping (String) -> Void) {
        self.prompt = prompt
        self.print = print
    }
}

public struct ReviewSession {
    public static let order: [ScannerID] = [.dockerContainers, .dockerImages, .dockerVolumes, .dockerBuildCache, .worktrees]
    static let itemLevel: Set<ScannerID> = [.dockerVolumes, .worktrees]

    let ctx: ScanContext
    let executor: Executor
    let io: ReviewIO
    let scan: (ScanContext, ScannerID) -> ScanResult
    let keep: (String) -> Void

    public init(
        ctx: ScanContext, executor: Executor, io: ReviewIO,
        scan: @escaping (ScanContext, ScannerID) -> ScanResult = { ScannerRegistry.scan($0, only: [$1]) },
        keep: @escaping (String) -> Void
    ) {
        self.ctx = ctx
        self.executor = executor
        self.io = io
        self.scan = scan
        self.keep = keep
    }

    public func run() throws -> [ExecutionResult] {
        var results: [ExecutionResult] = []
        for id in Self.order where ctx.tier(id) == .ask {
            let scanned = scan(ctx, id)
            scanned.errors.forEach { io.print("warning: \($0)") }
            let candidates = scanned.candidates.filter { $0.tier == .ask }
            guard let group = candidates.first?.group else {
                io.print("\(id.rawValue): nothing to review")
                continue
            }
            let outcome = Self.itemLevel.contains(id) ? reviewItems(candidates, group: group) : reviewGroup(candidates, group: group)
            results += outcome.results
            if outcome.quit { break }
        }
        return results
    }

    func reviewGroup(_ candidates: [Candidate], group: String) -> (results: [ExecutionResult], quit: Bool) {
        let total = candidates.reduce(0) { $0 + $1.sizeBytes }
        while true {
            switch answer("\(group): \(candidates.count) items, \(ByteFormat.string(total)) [y/n/l/q] ") {
            case "y": return (execute(candidates), false)
            case "n": return ([], false)
            case "l": candidates.forEach { io.print("  \(describe($0))") }
            case "q", nil: return ([], true)
            default: io.print("y = remove all, n = skip, l = list, q = quit")
            }
        }
    }

    func reviewItems(_ candidates: [Candidate], group: String) -> (results: [ExecutionResult], quit: Bool) {
        var results: [ExecutionResult] = []
        io.print("\(group): \(candidates.count) items")
        for candidate in candidates {
            var decided = false
            while !decided {
                let hint = candidate.scanner == .worktrees ? "[y/n/k/q] " : "[y/n/q] "
                switch answer("  \(describe(candidate)) \(hint)") {
                case "y": results += execute([candidate]); decided = true
                case "n": decided = true
                case "k" where candidate.scanner == .worktrees:
                    keep(candidate.id)
                    io.print("  kept: \(candidate.label)")
                    decided = true
                case "q", nil: return (results, true)
                default: io.print("y = remove, n = skip" + (candidate.scanner == .worktrees ? ", k = keep forever" : "") + ", q = quit")
                }
            }
        }
        return (results, false)
    }

    func execute(_ candidates: [Candidate]) -> [ExecutionResult] {
        candidates.map { candidate in
            let result = executor.execute(candidate)
            io.print("  \(result.ok ? "ok" : "FAILED") \(candidate.label) (\(ByteFormat.string(candidate.sizeBytes)))\(result.ok ? "" : ": \(result.message)")")
            return result
        }
    }

    func describe(_ candidate: Candidate) -> String {
        let detail = candidate.detail.map { ", \($0)" } ?? ""
        return "\(candidate.label) (\(ByteFormat.string(candidate.sizeBytes))\(detail))"
    }

    func answer(_ prompt: String) -> String? {
        io.prompt(prompt)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
