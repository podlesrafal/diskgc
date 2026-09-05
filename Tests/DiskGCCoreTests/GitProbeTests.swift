import Foundation
import Testing
@testable import DiskGCCore

struct TempRepo {
    let root: String
    let repo: String
    let shell = ProcessShell()

    init() throws {
        root = TestSupport.tempDir("repo")
        repo = "\(root)/main"
        TestSupport.mkdir(repo)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.email", "t@example.com"])
        try git(["config", "user.name", "t"])
        TestSupport.touch("\(repo)/.gitignore", content: "node_modules/\ntarget/\n")
        TestSupport.touch("\(repo)/README.md", content: "hi")
        try git(["add", "."])
        try git(["commit", "-q", "-m", "init"])
    }

    @discardableResult
    func git(_ args: [String]) throws -> String {
        let result = try shell.run("git", ["-C", repo] + args, cwd: nil)
        guard result.succeeded else { throw FakeShell.Error.unexpected(result.stderr) }
        return result.stdout
    }

    func addWorktree(_ name: String, branch: String? = nil, detached: Bool = false) throws -> String {
        let path = "\(root)/wt-\(name)"
        if detached {
            try git(["worktree", "add", "-q", "--detach", path])
        } else {
            try git(["worktree", "add", "-q", "-b", branch ?? name, path])
        }
        return path
    }
}

@Suite struct GitProbeTests {
    let probe = GitProbe(shell: ProcessShell(), fs: FileManager.default)

    @Test func parsesWorktreeListPorcelain() {
        let porcelain = """
        worktree /repo
        HEAD aaaa
        branch refs/heads/main

        worktree /wt/feature
        HEAD bbbb
        branch refs/heads/feat/x

        worktree /wt/detached
        HEAD cccc
        detached

        worktree /wt/gone
        HEAD dddd
        branch refs/heads/gone
        prunable gitdir file points to non-existent location

        """
        let entries = GitProbe.parseWorktreeList(porcelain)
        #expect(entries == [
            WorktreeEntry(path: "/repo", head: "aaaa", branch: "main", detached: false, prunable: false, isMain: true),
            WorktreeEntry(path: "/wt/feature", head: "bbbb", branch: "feat/x", detached: false, prunable: false, isMain: false),
            WorktreeEntry(path: "/wt/detached", head: "cccc", branch: nil, detached: true, prunable: false, isMain: false),
            WorktreeEntry(path: "/wt/gone", head: "dddd", branch: "gone", detached: false, prunable: true, isMain: false),
        ])
    }

    @Test func probesRealRepository() throws {
        let repo = try TempRepo()
        TestSupport.mkdir("\(repo.repo)/node_modules/pkg")
        TestSupport.mkdir("\(repo.repo)/scripts/build")
        #expect(probe.toplevel(of: "\(repo.repo)/node_modules/pkg") == repo.repo)
        #expect(probe.toplevel(of: repo.root) == nil)
        #expect(probe.gitDir(of: repo.repo) == "\(repo.repo)/.git")
        #expect(probe.isIgnored("\(repo.repo)/node_modules", in: repo.repo))
        #expect(!probe.isIgnored("\(repo.repo)/scripts/build", in: repo.repo))
        #expect(probe.isClean(repo.repo))
        TestSupport.touch("\(repo.repo)/dirty.txt")
        #expect(!probe.isClean(repo.repo))
        #expect(probe.indexModificationDate(of: repo.repo) != nil)
    }

    @Test func listsLinkedWorktrees() throws {
        let repo = try TempRepo()
        let feature = try repo.addWorktree("feature")
        let detached = try repo.addWorktree("det", detached: true)
        let entries = probe.worktrees(of: repo.repo)
        #expect(entries.count == 3)
        #expect(entries[0].isMain && entries[0].path == repo.repo)
        #expect(entries.contains { $0.path == feature && $0.branch == "feature" && !$0.isMain })
        #expect(entries.contains { $0.path == detached && $0.detached })
        #expect(probe.gitDir(of: feature) == "\(repo.repo)/.git/worktrees/wt-feature")
        #expect(probe.toplevel(of: feature) == feature)
        #expect(probe.indexModificationDate(of: feature) != nil)
    }
}
