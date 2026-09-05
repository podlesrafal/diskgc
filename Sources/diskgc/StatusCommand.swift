import ArgumentParser
import Foundation
import DiskGCCore

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show free space and reclaimable candidates per tier.")

    @Flag(name: .long, help: "Ignore cached sizes and measure everything again.")
    var rescan = false

    @Flag(name: .long, help: "Print the report as JSON.")
    var json = false

    @Flag(name: .shortAndLong, help: "List every candidate inside each group.")
    var verbose = false

    func run() throws {
        let env = try Environment()
        let sizes = env.sizeProbe(rescan: rescan)
        let scanned = ScannerRegistry.scan(env.context(sizes: sizes))
        let report = StatusReport(generatedAt: Date(), freeBytes: try env.freeBytes(), targetBytes: env.targetBytes, candidates: scanned.candidates, errors: scanned.errors)
        try env.save(env.state, sizes: sizes)
        print(json ? try report.json() : report.render(verbose: verbose))
    }
}
