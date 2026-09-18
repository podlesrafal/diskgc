import ArgumentParser
import Foundation
import DiskGCCore

struct CleanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "clean", abstract: "Run the auto tier now.")

    @Flag(name: .long, help: "Plan and report without deleting.")
    var dryRun = false

    @Flag(name: .long, help: "Remove every auto candidate instead of stopping at the free-space target.")
    var all = false

    @Option(name: .long, help: "Limit to one scanner (\(ScannerID.allCases.map(\.rawValue).joined(separator: ", "))).")
    var scanner: String?

    func run() throws {
        let env = try Runtime()
        let only: Set<ScannerID>? = try scanner.map { name in
            guard let id = ScannerID(rawValue: name) else { throw ValidationError("unknown scanner: \(name)") }
            return [id]
        }
        let sizes = env.sizeProbe(rescan: false)
        let ctx = env.context(sizes: sizes)
        let executor = env.executor(dryRun: dryRun)
        let scan: (ScanContext) -> ScanResult = { ScannerRegistry.scan($0, only: only) }
        if all {
            let scanned = scan(ctx)
            let auto = PressurePlanner.order(scanned.candidates.filter { $0.tier == .auto })
            let executed = auto.map(executor.execute)
            let free = try env.freeBytes()
            Output.tick(TickReport(freeBefore: free, freeAfter: try env.freeBytes(), target: env.targetBytes, candidates: scanned.candidates, errors: scanned.errors, executed: executed, askTotal: 0, notified: false, state: env.state), dryRun: dryRun)
        } else {
            let tick = Tick(ctx: ctx, executor: executor, notifier: PrintingNotifier(output: { _ in }), freeBytes: env.freeBytes, scan: scan)
            var report = try tick.run()
            report.state.lastNotifiedAt = env.state.lastNotifiedAt
            Output.tick(report, dryRun: dryRun)
        }
        if !dryRun { try env.save(env.state, sizes: sizes) }
    }
}
