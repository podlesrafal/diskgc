import ArgumentParser
import Foundation
import DiskGCCore

struct LogCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "log", abstract: "Show the journal of performed and planned actions.")

    @Option(name: .long, help: "Number of newest entries to show.")
    var limit = 50

    func run() throws {
        let env = try Runtime()
        let formatter = ISO8601DateFormatter()
        for entry in try env.journal.read(limit: limit) {
            let status = entry.dryRun ? "dry-run" : (entry.error == "pending" ? "pending" : (entry.ok ? "ok" : "FAILED"))
            let error = entry.ok || entry.error == "pending" ? "" : " - \(entry.error ?? "")"
            print("\(formatter.string(from: entry.at)) \(status.padding(toLength: 7, withPad: " ", startingAt: 0)) \(entry.scanner.rawValue) \(ByteFormat.string(entry.sizeBytes)) \(entry.action)\(error)")
        }
    }
}
