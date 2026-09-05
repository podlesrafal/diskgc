import Foundation
import Testing
@testable import DiskGCCore

@Suite struct WorktreeScannerTests {
    func context(root: String, kept: [String] = [], active: [String] = []) -> ScanContext {
        var ctx = ScanContext.test(home: "/nonexistent", roots: [root], activeCwds: active)
        ctx.state.keptWorktrees = kept
        return ctx
    }

    func age(_ repo: TempRepo, worktree name: String, days: Int) {
        TestSupport.setModificationDate("\(repo.repo)/.git/worktrees/wt-\(name)/index", daysAgo: days)
    }

    @Test func freshWorktreeIsNotACandidate() throws {
        let repo = try TempRepo()
        _ = try repo.addWorktree("fresh")
        #expect(try WorktreeScanner().scan(context(root: repo.root)).isEmpty)
    }

    @Test func idleCleanWorktreeIsAnAskCandidate() throws {
        let repo = try TempRepo()
        let path = try repo.addWorktree("idle")
        age(repo, worktree: "idle", days: 30)
        let found = try WorktreeScanner().scan(context(root: repo.root))
        #expect(found.count == 1)
        #expect(found[0].id == path)
        #expect(found[0].tier == .ask)
        #expect(found[0].staleDays == 30)
        #expect(found[0].detail == "branch idle, 30d idle, repo \(repo.repo)")
        #expect(found[0].actions == [.worktreeRemove(repo: repo.repo, path: path)])
    }

    @Test func dirtyKeptOrInUseWorktreesAreSkipped() throws {
        let repo = try TempRepo()
        let dirty = try repo.addWorktree("dirty")
        TestSupport.touch("\(dirty)/wip.txt")
        let kept = try repo.addWorktree("kept")
        let busy = try repo.addWorktree("busy")
        let detached = try repo.addWorktree("det", detached: true)
        for name in ["dirty", "kept", "busy", "det"] { age(repo, worktree: name, days: 40) }
        let found = try WorktreeScanner().scan(context(root: repo.root, kept: [kept], active: ["\(busy)/src"]))
        #expect(found.map(\.id) == [detached])
        #expect(found[0].detail == "detached, 40d idle, repo \(repo.repo)")
    }

    @Test func missingWorktreeDirectoryYieldsAutoPruneCandidate() throws {
        let repo = try TempRepo()
        let gone = try repo.addWorktree("gone")
        try FileManager.default.removeItem(atPath: gone)
        let found = try WorktreeScanner().scan(context(root: repo.root))
        #expect(found.count == 1)
        #expect(found[0].tier == .auto)
        #expect(found[0].group == "Worktrees (prune)")
        #expect(found[0].actions == [.worktreePrune(repo: repo.repo)])
    }

    @Test func findsRepositoriesBelowRootButNotInsideNodeModules() throws {
        let root = TestSupport.tempDir("roots")
        TestSupport.mkdir("\(root)/a/b/repo/.git")
        TestSupport.mkdir("\(root)/node_modules/pkg/.git")
        TestSupport.mkdir("\(root)/a/b/repo/nested/.git")
        #expect(WorktreeScanner.repositories(under: root, depth: 0, fs: .default) == ["\(root)/a/b/repo"])
    }
}
