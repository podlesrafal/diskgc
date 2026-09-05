import Foundation
import Testing
@testable import DiskGCCore

@Suite struct ExecutorTests {
    let fs = FileManager.default

    func candidate(_ actions: [Action], id: String = "c") -> Candidate {
        Candidate(scanner: .buildArtifacts, group: "Build artifacts", id: id, label: id, sizeBytes: 100, staleDays: 9, actions: actions)
    }

    func makeExecutor(dryRun: Bool, shell: FakeShell = FakeShell(), never: [String] = []) -> (Executor, Journal) {
        let journal = Journal(path: TestSupport.tempDir("journal") + "/journal.jsonl")
        let executor = Executor(shell: shell, fs: fs, never: never, journal: journal, dryRun: dryRun, now: { Date(timeIntervalSince1970: 0) })
        return (executor, journal)
    }

    @Test func dryRunDeletesNothingAndJournals() throws {
        let root = TestSupport.tempDir()
        let dir = "\(root)/proj/node_modules"
        TestSupport.mkdir(dir)
        let shell = FakeShell()
        let (executor, journal) = makeExecutor(dryRun: true, shell: shell)
        let result = executor.execute(candidate([.removeDirectory(path: dir, root: root), .run(command: "uv", arguments: ["cache", "clean"])]))
        #expect(result.ok)
        #expect(fs.fileExists(atPath: dir))
        #expect(shell.calls.isEmpty)
        let entries = try journal.read(limit: 10)
        #expect(entries.map(\.dryRun) == [true, true])
        #expect(entries.map(\.action) == ["rm -rf \(dir)", "uv cache clean"])
    }

    @Test func removesDirectoryAndJournalsPendingThenResult() throws {
        let root = TestSupport.tempDir()
        let dir = "\(root)/proj/node_modules"
        TestSupport.touch("\(dir)/x/y.txt")
        let (executor, journal) = makeExecutor(dryRun: false)
        let result = executor.execute(candidate([.removeDirectory(path: dir, root: root)]))
        #expect(result.ok)
        #expect(!fs.fileExists(atPath: dir))
        #expect(fs.fileExists(atPath: "\(root)/proj"))
        let entries = try journal.read(limit: 10)
        #expect(entries.count == 2)
        #expect(entries[0].ok == false && entries[0].error == "pending")
        #expect(entries[1].ok == true && entries[1].error == nil && entries[1].dryRun == false)
    }

    @Test func removeContentsKeepsDirectory() throws {
        let root = TestSupport.tempDir()
        let dir = "\(root)/cache/yarn"
        TestSupport.touch("\(dir)/a/1.zip")
        TestSupport.touch("\(dir)/b.zip")
        let (executor, _) = makeExecutor(dryRun: false)
        let result = executor.execute(candidate([.removeContents(path: dir, root: root)]))
        #expect(result.ok)
        #expect(fs.fileExists(atPath: dir))
        #expect(try fs.contentsOfDirectory(atPath: dir).isEmpty)
    }

    @Test func refusesSymlinkAndLeavesTargetIntact() throws {
        let root = TestSupport.tempDir()
        let real = "\(root)/proj/real"
        TestSupport.touch("\(real)/keep.txt")
        let link = "\(root)/proj/link"
        try fs.createSymbolicLink(atPath: link, withDestinationPath: real)
        let (executor, journal) = makeExecutor(dryRun: false)
        let result = executor.execute(candidate([.removeDirectory(path: link, root: root)]))
        #expect(!result.ok)
        #expect(result.message.contains("symlink"))
        #expect(fs.fileExists(atPath: "\(real)/keep.txt"))
        #expect(try journal.read(limit: 10).last?.ok == false)
    }

    @Test func refusesPathsUnderNever() throws {
        let root = TestSupport.tempDir()
        let dir = "\(root)/m2/repository"
        TestSupport.mkdir(dir)
        let (executor, _) = makeExecutor(dryRun: false, never: ["\(root)/m2"])
        let result = executor.execute(candidate([.removeDirectory(path: dir, root: root)]))
        #expect(!result.ok)
        #expect(fs.fileExists(atPath: dir))
    }

    @Test func runActionFailsOnNonZeroStatus() {
        let shell = FakeShell()
        shell.responses["uv cache clean"] = ShellResult(status: 1, stdout: "", stderr: "nope")
        let (executor, _) = makeExecutor(dryRun: false, shell: shell)
        let result = executor.execute(candidate([.run(command: "uv", arguments: ["cache", "clean"])]))
        #expect(!result.ok)
        #expect(result.message.contains("nope"))
    }

    @Test func stopsAtFirstFailingAction() {
        let shell = FakeShell()
        shell.responses["first"] = ShellResult(status: 2, stdout: "", stderr: "")
        shell.responses["second"] = ShellResult(status: 0, stdout: "", stderr: "")
        let (executor, _) = makeExecutor(dryRun: false, shell: shell)
        let result = executor.execute(candidate([.run(command: "first", arguments: []), .run(command: "second", arguments: [])]))
        #expect(!result.ok)
        #expect(shell.calls == ["first"])
    }

    @Test func worktreeActionsUseGitWithoutForce() {
        let shell = FakeShell()
        shell.respond("git", ["-C", "/repo", "worktree", "remove", "/repo-wt/x"], stdout: "")
        shell.respond("git", ["-C", "/repo", "worktree", "prune"], stdout: "")
        let (executor, _) = makeExecutor(dryRun: false, shell: shell)
        let result = executor.execute(candidate([.worktreeRemove(repo: "/repo", path: "/repo-wt/x"), .worktreePrune(repo: "/repo")]))
        #expect(result.ok)
        #expect(shell.calls == ["git -C /repo worktree remove /repo-wt/x", "git -C /repo worktree prune"])
    }

    @Test func describesActions() {
        #expect(Executor.describe(.removeDirectory(path: "/p", root: "/")) == "rm -rf /p")
        #expect(Executor.describe(.removeContents(path: "/p", root: "/")) == "rm -rf /p/*")
        #expect(Executor.describe(.run(command: "uv", arguments: ["cache", "clean"])) == "uv cache clean")
        #expect(Executor.describe(.worktreeRemove(repo: "/r", path: "/w")) == "git -C /r worktree remove /w")
        #expect(Executor.describe(.worktreePrune(repo: "/r")) == "git -C /r worktree prune")
    }
}
