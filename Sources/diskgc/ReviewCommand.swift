import ArgumentParser
import Foundation
import DiskGCCore

struct ReviewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "review", abstract: "Walk through Docker resources and git worktrees and decide what to remove.")

    @Flag(name: .long, help: "Answer as usual but delete nothing.")
    var dryRun = false

    func run() throws {
        let env = try Environment()
        let sizes = env.sizeProbe(rescan: false)
        var state = env.state
        let io = ReviewIO(
            prompt: { text in
                print(text, terminator: "")
                return readLine()
            },
            print: { print($0) }
        )
        let session = ReviewSession(ctx: env.context(sizes: sizes), executor: env.executor(dryRun: dryRun), io: io, keep: { path in
            state.keptWorktrees.append(path)
            try? env.save(state, sizes: sizes)
        })
        let results = try session.run()
        let freed = results.filter(\.ok).reduce(0) { $0 + $1.candidate.sizeBytes }
        print("\(dryRun ? "would reclaim" : "reclaimed") \(ByteFormat.string(freed)); free now \(ByteFormat.string(try env.freeBytes()))")
        if !dryRun { try env.save(state, sizes: sizes) }
    }
}
