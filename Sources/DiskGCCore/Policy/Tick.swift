import Foundation

public struct TickReport: Equatable {
    public var freeBefore: Int64
    public var freeAfter: Int64
    public var target: Int64
    public var candidates: [Candidate]
    public var errors: [String]
    public var executed: [ExecutionResult]
    public var askTotal: Int64
    public var notified: Bool
    public var warned: Bool
    public var state: State

    public init(freeBefore: Int64, freeAfter: Int64, target: Int64, candidates: [Candidate], errors: [String], executed: [ExecutionResult], askTotal: Int64, notified: Bool, warned: Bool = false, state: State) {
        self.freeBefore = freeBefore
        self.freeAfter = freeAfter
        self.target = target
        self.candidates = candidates
        self.errors = errors
        self.executed = executed
        self.askTotal = askTotal
        self.notified = notified
        self.warned = warned
        self.state = state
    }
}

public struct Tick {
    public let ctx: ScanContext
    public let executor: Executor
    public let notifier: Notifier
    public let freeBytes: () throws -> Int64
    public let scan: (ScanContext) -> ScanResult

    public init(
        ctx: ScanContext, executor: Executor, notifier: Notifier,
        freeBytes: @escaping () throws -> Int64, scan: @escaping (ScanContext) -> ScanResult = { ScannerRegistry.scan($0) }
    ) {
        self.ctx = ctx
        self.executor = executor
        self.notifier = notifier
        self.freeBytes = freeBytes
        self.scan = scan
    }

    public func run() throws -> TickReport {
        let freeBefore = try freeBytes()
        let target = Int64(ctx.config.targetFreeGB) * ByteFormat.gigabyte
        let scanned = scan(ctx)
        var free = freeBefore
        var executed: [ExecutionResult] = []
        for candidate in PressurePlanner.order(scanned.candidates.filter { $0.tier == .auto }) where free < target {
            let result = executor.execute(candidate)
            executed.append(result)
            free = executor.dryRun ? free + (result.ok ? candidate.sizeBytes : 0) : try freeBytes()
        }
        let ask = scanned.candidates.filter { $0.tier == .ask }
        let askTotal = ask.reduce(0) { $0 + $1.sizeBytes }
        var state = ctx.state
        var notified = false
        var warned = false
        let warnBelow = Int64(ctx.config.warnFreeGB) * ByteFormat.gigabyte
        if free < warnBelow, cooldownPassed(state.lastWarnedAt, hours: ctx.config.warnCooldownHours) {
            notifier.notify(
                title: "Running low on space",
                message: Self.warning(free: free, reclaimed: freeBefore < free ? free - freeBefore : 0, ask: ask, executed: executed)
            )
            state.lastWarnedAt = ctx.now
            warned = true
        } else if askTotal >= Int64(ctx.config.notifyMinGB) * ByteFormat.gigabyte,
                  cooldownPassed(state.lastNotifiedAt, hours: ctx.config.notifyCooldownHours) {
            notifier.notify(title: "diskgc", message: Self.message(for: ask))
            state.lastNotifiedAt = ctx.now
            notified = true
        }
        return TickReport(
            freeBefore: freeBefore, freeAfter: free, target: target, candidates: scanned.candidates, errors: scanned.errors,
            executed: executed, askTotal: askTotal, notified: notified, warned: warned, state: state
        )
    }

    func cooldownPassed(_ last: Date?, hours: Int) -> Bool {
        guard let last else { return true }
        return ctx.now.timeIntervalSince(last) >= Double(hours) * 3600
    }

    public static func warning(free: Int64, reclaimed: Int64, ask: [Candidate], executed: [ExecutionResult]) -> String {
        var parts = ["\(ByteFormat.gigabytes(free)) GB left"]
        if reclaimed > 0 { parts.append("auto freed \(ByteFormat.gigabytes(reclaimed)) GB") }
        let askTotal = ask.reduce(0) { $0 + $1.sizeBytes }
        if askTotal > 0 { parts.append("\(ByteFormat.gigabytes(askTotal)) GB you can reclaim \u{2014} click to review") }
        let failed = executed.filter { !$0.ok }.map(\.candidate.label)
        if !failed.isEmpty { parts.append("failed: \(failed.joined(separator: ", "))") }
        return parts.joined(separator: ", ")
    }

    public static func message(for ask: [Candidate]) -> String {
        let total = ask.reduce(0) { $0 + $1.sizeBytes }
        let docker = ask.filter { $0.scanner.rawValue.hasPrefix("docker") }.reduce(0) { $0 + $1.sizeBytes }
        let worktrees = ask.filter { $0.scanner == .worktrees }.reduce(0) { $0 + $1.sizeBytes }
        var parts: [String] = []
        if docker > 0 { parts.append("Docker \(ByteFormat.gigabytes(docker)) GB") }
        if worktrees > 0 { parts.append("worktrees \(ByteFormat.gigabytes(worktrees)) GB") }
        let breakdown = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
        return "\(ByteFormat.gigabytes(total)) GB you can reclaim\(breakdown) \u{2014} click to review"
    }
}
