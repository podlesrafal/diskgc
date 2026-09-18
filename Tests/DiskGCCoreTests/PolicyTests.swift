import Foundation
import Testing
@testable import DiskGCCore

final class RecordingNotifier: Notifier {
    var messages: [String] = []
    func notify(title: String, message: String) { messages.append(message) }
}

struct StubScanner: DiskScanner {
    var id: ScannerID
    var candidates: [Candidate]
    func scan(_ ctx: ScanContext) throws -> [Candidate] { candidates }
}

@Suite struct PolicyTests {
    func candidate(_ id: String, scanner: ScannerID = .buildArtifacts, tier: Tier = .auto, size: Int64, stale: Int, actions: [Action] = []) -> Candidate {
        Candidate(scanner: scanner, tier: tier, group: scanner.rawValue, id: id, label: id, sizeBytes: size, staleDays: stale, actions: actions)
    }

    @Test func plannerOrdersByStalenessThenSize() {
        let ordered = PressurePlanner.order([
            candidate("small-old", size: 1, stale: 10), candidate("big-new", size: 100, stale: 1),
            candidate("big-old", size: 100, stale: 10), candidate("a", size: 100, stale: 10),
        ])
        #expect(ordered.map(\.id) == ["a", "big-old", "small-old", "big-new"])
    }

    @Test func registryHonoursTiersAndFilters() {
        var config = Config.default
        config.scanners[.xcode] = .off
        let ctx = ScanContext(config: config, shell: FakeShell(), sizes: FixedSizeProbe(), home: "/nonexistent")
        let scanners: [DiskScanner] = [
            StubScanner(id: .xcode, candidates: [candidate("x", scanner: .xcode, size: 1, stale: 1)]),
            StubScanner(id: .toolCaches, candidates: [candidate("t", scanner: .toolCaches, size: 1, stale: 1)]),
            StubScanner(id: .worktrees, candidates: [candidate("w", scanner: .worktrees, size: 1, stale: 1)]),
        ]
        #expect(ScannerRegistry.scan(ctx, scanners: scanners).candidates.map(\.id) == ["t", "w"])
        #expect(ScannerRegistry.scan(ctx, only: [.worktrees], scanners: scanners).candidates.map(\.id) == ["w"])
    }

    struct Harness {
        let root: String
        let dirs: [String]
        let notifier = RecordingNotifier()
        let shell = FakeShell()
        var frees: [Int64]
        let journal: Journal

        init(freeSequence: [Int64]) {
            root = TestSupport.tempDir("tick")
            dirs = ["\(root)/p/a", "\(root)/p/b", "\(root)/p/c"]
            dirs.forEach(TestSupport.mkdir)
            frees = freeSequence
            journal = Journal(path: "\(root)/journal.jsonl")
        }

        func tick(config: Config, state: State = State(), dryRun: Bool = false, ask: [Candidate] = []) throws -> TickReport {
            let ctx = ScanContext(config: config, shell: shell, sizes: FixedSizeProbe(), now: Date(timeIntervalSince1970: 1_000_000), home: "/nonexistent", state: state)
            let auto = zip(dirs, [(30, Int64(1 * ByteFormat.gigabyte)), (10, 2 * ByteFormat.gigabyte), (20, 3 * ByteFormat.gigabyte)]).map { dir, meta in
                Candidate(scanner: .buildArtifacts, tier: .auto, group: "Build artifacts", id: dir, label: dir, sizeBytes: meta.1, staleDays: meta.0, actions: [.removeDirectory(path: dir, root: root)])
            }
            let executor = Executor(shell: shell, fs: .default, never: [], journal: journal, dryRun: dryRun)
            var remaining = frees
            let tick = Tick(ctx: ctx, executor: executor, notifier: notifier, freeBytes: { remaining.count > 1 ? remaining.removeFirst() : remaining[0] }, scan: { _ in ScanResult(candidates: auto + ask) })
            return try tick.run()
        }
    }

    @Test func noPressureExecutesNothing() throws {
        var config = Config.default
        config.targetFreeGB = 10
        let harness = Harness(freeSequence: [20 * ByteFormat.gigabyte])
        let report = try harness.tick(config: config)
        #expect(report.executed.isEmpty)
        let allExist = harness.dirs.allSatisfy { FileManager.default.fileExists(atPath: $0) }
        #expect(allExist)
        #expect(!report.notified)
    }

    @Test func pressureExecutesMostStaleFirstUntilTargetReached() throws {
        var config = Config.default
        config.targetFreeGB = 10
        let gb = ByteFormat.gigabyte
        let harness = Harness(freeSequence: [5 * gb, 6 * gb, 11 * gb])
        let report = try harness.tick(config: config)
        #expect(report.executed.map(\.candidate.id) == ["\(harness.root)/p/a", "\(harness.root)/p/c"])
        #expect(report.executed.map(\.ok) == [true, true])
        #expect(!FileManager.default.fileExists(atPath: "\(harness.root)/p/a"))
        #expect(!FileManager.default.fileExists(atPath: "\(harness.root)/p/c"))
        #expect(FileManager.default.fileExists(atPath: "\(harness.root)/p/b"))
        #expect(report.freeAfter == 11 * gb)
    }

    @Test func dryRunSimulatesFreedSpace() throws {
        var config = Config.default
        config.targetFreeGB = 10
        let gb = ByteFormat.gigabyte
        let harness = Harness(freeSequence: [7 * gb])
        let report = try harness.tick(config: config, dryRun: true)
        #expect(report.executed.map(\.candidate.id) == ["\(harness.root)/p/a", "\(harness.root)/p/c"])
        let allExist = harness.dirs.allSatisfy { FileManager.default.fileExists(atPath: $0) }
        #expect(allExist)
        #expect(report.freeAfter == 11 * gb)
    }

    @Test func notifiesAboutAskTierWithCooldown() throws {
        var config = Config.default
        config.targetFreeGB = 1
        let gb = ByteFormat.gigabyte
        let ask = [
            candidate("c1", scanner: .dockerContainers, tier: .ask, size: 4 * gb, stale: 5),
            candidate("w1", scanner: .worktrees, tier: .ask, size: 2 * gb, stale: 30),
        ]
        let harness = Harness(freeSequence: [50 * gb])
        let first = try harness.tick(config: config, ask: ask)
        #expect(first.notified)
        #expect(harness.notifier.messages == ["6.0 GB you can reclaim (Docker 4.0 GB, worktrees 2.0 GB) \u{2014} click to review"])
        #expect(first.state.lastNotifiedAt == Date(timeIntervalSince1970: 1_000_000))
        let second = try harness.tick(config: config, state: first.state, ask: ask)
        #expect(!second.notified)
        #expect(harness.notifier.messages.count == 1)
        let tooSmall = try harness.tick(config: config, ask: [ask[1]])
        #expect(!tooSmall.notified)
    }

    @Test func warnsWhileFreeSpaceStaysBelowThreshold() throws {
        var config = Config.default
        config.warnFreeGB = 15
        let gb = ByteFormat.gigabyte
        let ask = [candidate("w1", scanner: .worktrees, tier: .ask, size: 1 * gb, stale: 30)]
        let harness = Harness(freeSequence: [4 * gb])
        let report = try harness.tick(config: config, ask: ask)
        #expect(report.warned)
        #expect(!report.notified)
        #expect(harness.notifier.messages == ["4.0 GB left, 1.0 GB you can reclaim \u{2014} click to review"])
        #expect(report.state.lastWarnedAt == Date(timeIntervalSince1970: 1_000_000))
        let second = try harness.tick(config: config, state: report.state, ask: ask)
        #expect(!second.warned)
        #expect(harness.notifier.messages.count == 1)
    }

    @Test func warningNamesFailedAutoActions() {
        let failed = ExecutionResult(
            candidate: candidate("pnpm", scanner: .toolCaches, size: 2 * ByteFormat.gigabyte, stale: 1),
            ok: false, message: "commandNotFound"
        )
        let text = Tick.warning(free: 3 * ByteFormat.gigabyte, reclaimed: ByteFormat.gigabyte, ask: [], executed: [failed])
        #expect(text == "3.0 GB left, auto freed 1.0 GB, failed: pnpm")
    }
}
