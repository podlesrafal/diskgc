import Foundation
import Testing
@testable import DiskGCCore

struct FixedSizeProbe: SizeProbe {
    var size: Int64 = 1_000
    func sizeBytes(of path: String) throws -> Int64 { size }
}

extension ScanContext {
    static func test(home: String, roots: [String] = [], tmpRoot: String = "/nonexistent", activeCwds: [String] = [], environment: [String: String] = [:]) -> ScanContext {
        var config = Config.default
        config.projectRoots = roots
        return ScanContext(config: config, shell: ProcessShell(), sizes: FixedSizeProbe(), home: home, activeCwds: activeCwds, tmpRoot: tmpRoot, environment: environment)
    }
}

@Suite struct AutoScannerTests {
    @Test func toolCachesOnlyForExistingDirectories() throws {
        let home = TestSupport.tempDir("home")
        TestSupport.touch("\(home)/.cache/uv/x")
        TestSupport.mkdir("\(home)/go/pkg/mod")
        let found = try ToolCacheScanner().scan(.test(home: home))
        #expect(found.map(\.label) == ["uv", "go-mod"])
        #expect(found[0].actions == [.removeContents(path: "\(home)/.cache/uv", root: home)])
        #expect(found[1].actions == [.run(command: "go", arguments: ["clean", "-modcache"])])
        #expect(found.allSatisfy { $0.group == "Tool caches" && $0.sizeBytes == 1_000 })
    }

    @Test func toolCachesHonourGoModCacheEnvironment() throws {
        let home = TestSupport.tempDir("home")
        TestSupport.mkdir("\(home)/custom/mod")
        let found = try ToolCacheScanner().scan(.test(home: home, environment: ["GOMODCACHE": "\(home)/custom/mod"]))
        #expect(found.map(\.id) == ["\(home)/custom/mod"])
    }

    @Test func updaterCachesRequireAge() throws {
        let home = TestSupport.tempDir("home")
        let old = "\(home)/Library/Caches/com.example.ShipIt"
        let fresh = "\(home)/Library/Caches/foo-updater"
        let docker = "\(home)/Library/Application Support/com.docker.install"
        TestSupport.mkdir(old); TestSupport.setModificationDate(old, daysAgo: 10)
        TestSupport.mkdir(fresh)
        TestSupport.mkdir(docker); TestSupport.setModificationDate(docker, daysAgo: 30)
        TestSupport.mkdir("\(home)/Library/Caches/Unrelated"); TestSupport.setModificationDate("\(home)/Library/Caches/Unrelated", daysAgo: 100)
        let found = try UpdaterCacheScanner().scan(.test(home: home))
        #expect(found.map(\.id).sorted() == [old, docker].sorted())
        #expect(found.first { $0.id == docker }?.actions == [.removeDirectory(path: docker, root: "\(home)/Library/Application Support")])
    }

    @Test func jetbrainsStaleVersionsOnly() throws {
        let home = TestSupport.tempDir("home")
        let old = "\(home)/Library/Caches/JetBrains/IntelliJIdea2026.1"
        let fresh = "\(home)/Library/Caches/JetBrains/IntelliJIdea2026.2"
        let logs = "\(home)/Library/Logs/JetBrains/IntelliJIdea2026.1"
        TestSupport.mkdir(old); TestSupport.setModificationDate(old, daysAgo: 45)
        TestSupport.touch("\(fresh)/caches/x"); TestSupport.setModificationDate(fresh, daysAgo: 45)
        TestSupport.mkdir(logs); TestSupport.setModificationDate(logs, daysAgo: 31)
        let found = try JetBrainsScanner().scan(.test(home: home))
        #expect(found.map(\.id) == [old, logs])
        #expect(found[0].staleDays == 45)
        #expect(found[0].actions == [.removeDirectory(path: old, root: "\(home)/Library/Caches/JetBrains")])
    }

    @Test func xcodeKeepsNewestDeviceSupportAndOldDerivedData() throws {
        let home = TestSupport.tempDir("home")
        let support = "\(home)/Library/Developer/Xcode/iOS DeviceSupport"
        for name in ["iPhone15,2 26.4.1 (23E254)", "iPhone15,2 26.5 (23F77)", "iPad13,1 25.1 (22B83)", "iPhone15,2 26.10 (24A1)"] {
            TestSupport.mkdir("\(support)/\(name)")
        }
        let derived = "\(home)/Library/Developer/Xcode/DerivedData"
        TestSupport.mkdir("\(derived)/Old-abc"); TestSupport.setModificationDate("\(derived)/Old-abc", daysAgo: 20)
        TestSupport.mkdir("\(derived)/Fresh-def")
        let found = try XcodeScanner().scan(.test(home: home))
        #expect(found.map(\.label) == ["DerivedData/Old-abc", "iOS DeviceSupport/iPhone15,2 26.4.1 (23E254)", "iOS DeviceSupport/iPhone15,2 26.5 (23F77)"])
        #expect(found[1].detail == "superseded by iPhone15,2 26.10 (24A1)")
    }

    @Test func claudeScratchSkipsFreshInUseAndDirtySessions() throws {
        let tmp = TestSupport.tempDir("claude-tmp")
        let repo = try TempRepo()
        let dirtySession = "\(tmp)/proj-a/dirty"
        let cleanSession = "\(tmp)/proj-a/clean"
        let plainSession = "\(tmp)/proj-b/plain"
        let freshSession = "\(tmp)/proj-b/fresh"
        let busySession = "\(tmp)/proj-b/busy"
        TestSupport.mkdir("\(dirtySession)/scratchpad")
        TestSupport.mkdir("\(cleanSession)/scratchpad")
        TestSupport.mkdir("\(plainSession)/scratchpad")
        TestSupport.mkdir("\(freshSession)/scratchpad")
        TestSupport.mkdir("\(busySession)/scratchpad")
        try repo.git(["worktree", "add", "-q", "-b", "dirty", "\(dirtySession)/scratchpad/wt"])
        try repo.git(["worktree", "add", "-q", "-b", "clean", "\(cleanSession)/scratchpad/wt"])
        TestSupport.touch("\(dirtySession)/scratchpad/wt/untracked.txt")
        for session in [dirtySession, cleanSession, plainSession, busySession] {
            for path in [session, "\(session)/scratchpad"] { TestSupport.setModificationDate(path, daysAgo: 20) }
        }
        let found = try ClaudeScratchScanner().scan(.test(home: "/nonexistent", tmpRoot: tmp, activeCwds: ["\(busySession)/scratchpad"]))
        #expect(found.map(\.id) == [cleanSession, plainSession])
        #expect(found[0].actions == [.removeDirectory(path: cleanSession, root: tmp), .worktreePrune(repo: repo.repo)])
        #expect(found[1].actions == [.removeDirectory(path: plainSession, root: tmp)])
        #expect(found[0].label == "proj-a/clean")
    }

    @Test func buildArtifactsRequireIgnoredIdleAndUnused() throws {
        let repo = try TempRepo()
        let idle = repo.repo
        TestSupport.mkdir("\(idle)/node_modules/x")
        TestSupport.mkdir("\(idle)/sub/target")
        TestSupport.mkdir("\(idle)/scripts/build")
        TestSupport.setModificationDate("\(idle)/.git/index", daysAgo: 10)
        let busy = try repo.addWorktree("busy")
        TestSupport.mkdir("\(busy)/node_modules")
        TestSupport.setModificationDate("\(idle)/.git/worktrees/wt-busy/index", daysAgo: 10)
        let fresh = try repo.addWorktree("fresh")
        TestSupport.mkdir("\(fresh)/node_modules")
        TestSupport.mkdir("\(repo.root)/not-a-repo/node_modules")

        let found = try BuildArtifactScanner().scan(.test(home: "/nonexistent", roots: [repo.root], activeCwds: ["\(busy)/sub"]))
        #expect(found.map(\.id) == ["\(idle)/node_modules", "\(idle)/sub/target"])
        #expect(found[0].staleDays == 10)
        #expect(found[0].actions == [.removeDirectory(path: "\(idle)/node_modules", root: repo.root)])
        #expect(found[0].detail == "main idle 10d")
    }
}
