import ArgumentParser
import DiskGCCore

@main
struct Diskgc: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diskgc",
        abstract: "Reclaims disk space from caches, build artifacts, Docker and git worktrees.",
        version: "0.1.0",
        subcommands: []
    )
}
