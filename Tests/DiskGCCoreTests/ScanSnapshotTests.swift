import Foundation
import Testing
@testable import DiskGCCore

@Suite struct ScanSnapshotTests {
    func candidate(_ id: String) -> Candidate {
        Candidate(scanner: .worktrees, tier: .ask, group: "worktrees", id: id, label: id, sizeBytes: 1, staleDays: 0, actions: [])
    }

    @Test func roundTripsThroughDisk() throws {
        let path = TestSupport.tempDir() + "/nested/last-scan.json"
        let snapshot = ScanSnapshot(at: Date(timeIntervalSince1970: 1000), candidates: [candidate("/a")], errors: ["boom"])
        try snapshot.save(to: path)
        #expect(ScanSnapshot.load(from: path) == snapshot)
    }

    @Test func missingOrCorruptSnapshotIsAbsent() throws {
        #expect(ScanSnapshot.load(from: "/nonexistent/last-scan.json") == nil)
        let path = TestSupport.tempDir() + "/last-scan.json"
        try "not json".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(ScanSnapshot.load(from: path) == nil)
    }

    @Test func isFreshOnlyWithinMaxAge() {
        let snapshot = ScanSnapshot(at: Date(timeIntervalSince1970: 0), candidates: [], errors: [])
        #expect(snapshot.isFresh(maxAge: 600, now: Date(timeIntervalSince1970: 599)))
        #expect(!snapshot.isFresh(maxAge: 600, now: Date(timeIntervalSince1970: 600)))
    }

    @Test func forgetDropsRemovedCandidates() throws {
        let path = TestSupport.tempDir() + "/last-scan.json"
        try ScanSnapshot(at: Date(), candidates: [candidate("/a"), candidate("/b")], errors: []).save(to: path)
        try ScanSnapshot.forget(["/a"], at: path)
        #expect(ScanSnapshot.load(from: path)?.candidates.map(\.id) == ["/b"])
    }
}
