import ArgumentParser
import Foundation
import DiskGCCore

struct TickCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tick", abstract: "Run one pressure cycle (what launchd runs every 30 minutes).")

    @Flag(name: .long, help: "Plan and report without deleting or notifying.")
    var dryRun = false

    func run() throws {
        let env = try Environment()
        let sizes = env.sizeProbe(rescan: false)
        let notifier: Notifier = dryRun ? PrintingNotifier(output: { print($0) }) : OSAScriptNotifier(shell: env.shell)
        let tick = Tick(ctx: env.context(sizes: sizes), executor: env.executor(dryRun: dryRun), notifier: notifier, freeBytes: env.freeBytes)
        let report = try tick.run()
        if !dryRun { try env.save(report.state, sizes: sizes) }
        Output.tick(report, dryRun: dryRun)
    }
}

enum Output {
    static func tick(_ report: TickReport, dryRun: Bool) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        print("[\(stamp)] free \(ByteFormat.string(report.freeBefore)) -> \(ByteFormat.string(report.freeAfter)) (target \(ByteFormat.string(report.target)))\(dryRun ? " [dry-run]" : "")")
        for result in report.executed {
            let candidate = result.candidate
            print("  \(result.ok ? "ok" : "FAILED") \(candidate.group): \(candidate.label) \(ByteFormat.string(candidate.sizeBytes))\(result.ok ? "" : " - \(result.message)")")
        }
        if report.executed.isEmpty { print("  nothing removed") }
        print("  ask tier: \(ByteFormat.string(report.askTotal))\(report.notified ? " (notified)" : "")")
        if report.warned { print("  low space warning sent") }
        for error in report.errors { print("  warning: \(error)") }
    }
}
