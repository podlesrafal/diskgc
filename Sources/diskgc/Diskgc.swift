import ArgumentParser
import DiskGCCore

@main
struct Diskgc: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diskgc",
        abstract: "Reclaims disk space from caches, build artifacts, Docker and git worktrees.",
        version: "0.1.0",
        subcommands: [StatusCommand.self, TickCommand.self, CleanCommand.self, ReviewCommand.self, LogCommand.self, InstallCommand.self, UninstallCommand.self],
        defaultSubcommand: StatusCommand.self
    )
}
