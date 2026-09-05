import Foundation
import Testing
@testable import DiskGCCore

@Suite struct ConfigTests {
    @Test func emptyDocumentIsDefault() throws {
        #expect(try Config.parse(yaml: "") == .default)
    }

    @Test func partialDocumentOverridesOnlyGivenKeys() throws {
        let config = try Config.parse(yaml: "target_free_gb: 10\nscanners:\n  worktrees: off\ninactive_days:\n  worktree: 5\n")
        #expect(config.targetFreeGB == 10)
        #expect(config.notifyMinGB == 5)
        #expect(config.tier(of: .worktrees) == .off)
        #expect(config.tier(of: .dockerImages) == .ask)
        #expect(config.tier(of: .toolCaches) == .auto)
        #expect(config.inactiveDays.worktree == 5)
        #expect(config.inactiveDays.buildArtifacts == 7)
    }

    @Test func defaultsMatchSpec() {
        let c = Config.default
        #expect(c.targetFreeGB == 60)
        #expect(c.notifyMinGB == 5)
        #expect(c.notifyCooldownHours == 24)
        #expect(c.rescanHours == 6)
        #expect(c.projectRoots == ["~/Documents/Projects"])
        #expect(c.inactiveDays == InactiveDays(buildArtifacts: 7, worktree: 21, dockerContainer: 3, derivedData: 14, jetbrains: 30, claudeScratch: 14))
        #expect(c.never == ["~/.m2", "~/Library/Application Support/Claude"])
        for id in ScannerID.allCases {
            let expected: Tier = id.rawValue.hasPrefix("docker") || id == .worktrees ? .ask : .auto
            #expect(c.tier(of: id) == expected)
        }
    }

    @Test func expandedReplacesTilde() {
        let c = Config.default.expanded(home: "/Users/x")
        #expect(c.projectRoots == ["/Users/x/Documents/Projects"])
        #expect(c.never == ["/Users/x/.m2", "/Users/x/Library/Application Support/Claude"])
    }

    @Test func loadMissingFileGivesDefault() throws {
        let c = try Config.load(from: "/nonexistent/diskgc/config.yaml", home: "/Users/x")
        #expect(c == Config.default.expanded(home: "/Users/x"))
    }

    @Test func loadReadsFile() throws {
        let dir = NSTemporaryDirectory() + "diskgc-config-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/config.yaml"
        try "target_free_gb: 42\nproject_roots:\n  - ~/Code\n".write(toFile: path, atomically: true, encoding: .utf8)
        let c = try Config.load(from: path, home: "/Users/x")
        #expect(c.targetFreeGB == 42)
        #expect(c.projectRoots == ["/Users/x/Code"])
    }

    @Test func defaultYAMLRoundTrips() throws {
        #expect(try Config.parse(yaml: Config.default.defaultYAML) == .default)
    }
}
