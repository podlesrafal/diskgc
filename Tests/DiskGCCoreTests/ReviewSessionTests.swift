import Foundation
import Testing
@testable import DiskGCCore

@Suite struct ReviewSessionTests {
    final class Script {
        var answers: [String?]
        var printed: [String] = []
        var prompts: [String] = []
        var kept: [String] = []
        init(_ answers: [String?]) { self.answers = answers }
        var io: ReviewIO {
            ReviewIO(prompt: { [self] text in prompts.append(text); return answers.isEmpty ? nil : answers.removeFirst() }, print: { [self] in printed.append($0) })
        }
    }

    let gb = ByteFormat.gigabyte

    func candidates(for id: ScannerID) -> [Candidate] {
        switch id {
        case .dockerContainers:
            return [
                Candidate(scanner: id, tier: .ask, group: "Docker containers", id: "c1", label: "old-db", sizeBytes: gb, staleDays: 5, actions: [.run(command: "docker", arguments: ["rm", "c1"])]),
                Candidate(scanner: id, tier: .ask, group: "Docker containers", id: "c2", label: "old-api", sizeBytes: gb, staleDays: 6, actions: [.run(command: "docker", arguments: ["rm", "c2"])]),
            ]
        case .worktrees:
            return [
                Candidate(scanner: id, tier: .ask, group: "Worktrees", id: "/w/a", label: "~/w/a", detail: "branch a, 30d idle", sizeBytes: gb, staleDays: 30, actions: [.worktreeRemove(repo: "/r", path: "/w/a")]),
                Candidate(scanner: id, tier: .ask, group: "Worktrees", id: "/w/b", label: "~/w/b", detail: "detached, 40d idle", sizeBytes: gb, staleDays: 40, actions: [.worktreeRemove(repo: "/r", path: "/w/b")]),
            ]
        default:
            return []
        }
    }

    func session(_ script: Script, shell: FakeShell) -> ReviewSession {
        let ctx = ScanContext(config: .default, shell: shell, sizes: FixedSizeProbe(), home: "/nonexistent")
        let executor = Executor(shell: shell, fs: .default, never: [], journal: Journal(path: TestSupport.tempDir() + "/j.jsonl"), dryRun: false)
        return ReviewSession(ctx: ctx, executor: executor, io: script.io, scan: { _, id in ScanResult(candidates: candidates(for: id)) }, keep: { script.kept.append($0) })
    }

    @Test func listThenYesRemovesWholeGroupAndSkipsWithNo() throws {
        let shell = FakeShell()
        shell.respond("docker", ["rm", "c1"], stdout: "")
        shell.respond("docker", ["rm", "c2"], stdout: "")
        let script = Script(["l", "y", "n", "n"])
        let results = try session(script, shell: shell).run()
        #expect(results.map(\.candidate.id) == ["c1", "c2"])
        #expect(shell.calls == ["docker rm c1", "docker rm c2"])
        #expect(script.printed.contains("  old-db (1.0 GB)"))
        #expect(script.printed.contains("docker_images: nothing to review"))
        #expect(script.prompts.first == "Docker containers: 2 items, 2.0 GB [y/n/l/q] ")
    }

    @Test func keepPersistsWorktreeAndQuitStopsEarly() throws {
        let shell = FakeShell()
        shell.respond("git", ["-C", "/r", "worktree", "remove", "/w/b"], stdout: "")
        let script = Script(["n", "k", "y"])
        let results = try session(script, shell: shell).run()
        #expect(results.map(\.candidate.id) == ["/w/b"])
        #expect(script.kept == ["/w/a"])
        #expect(shell.calls == ["git -C /r worktree remove /w/b"])
    }

    @Test func quitAbortsRemainingGroups() throws {
        let shell = FakeShell()
        let script = Script(["q"])
        let results = try session(script, shell: shell).run()
        #expect(results.isEmpty)
        #expect(script.prompts.count == 1)
    }

    @Test func endOfInputBehavesLikeQuit() throws {
        let script = Script([])
        #expect(try session(script, shell: FakeShell()).run().isEmpty)
    }
}
