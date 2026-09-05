import Foundation
import Testing
@testable import DiskGCCore

@Suite struct StateTests {
    @Test func stateRoundTrips() throws {
        let path = TestSupport.tempDir() + "/nested/state.json"
        var state = State()
        state.sizes["/a"] = SizeEntry(mtime: 1, size: 2, at: Date(timeIntervalSince1970: 3))
        state.lastNotifiedAt = Date(timeIntervalSince1970: 100)
        state.keptWorktrees = ["/w"]
        try state.save(to: path)
        #expect(State.load(from: path) == state)
    }

    @Test func missingOrCorruptStateIsEmpty() throws {
        #expect(State.load(from: "/nonexistent/state.json") == State())
        let path = TestSupport.tempDir() + "/state.json"
        try "not json".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(State.load(from: path) == State())
    }

    @Test func journalAppendsAndReadsNewestLast() throws {
        let path = TestSupport.tempDir() + "/logs/journal.jsonl"
        let journal = Journal(path: path)
        let first = JournalEntry(at: Date(timeIntervalSince1970: 1), scanner: .toolCaches, id: "uv", label: "uv cache", sizeBytes: 10, action: "uv cache clean", dryRun: true, ok: true, error: nil)
        let second = JournalEntry(at: Date(timeIntervalSince1970: 2), scanner: .xcode, id: "/d", label: "DerivedData", sizeBytes: 20, action: "rm -rf /d", dryRun: false, ok: false, error: "boom")
        try journal.append(first)
        try journal.append(second)
        #expect(try journal.read(limit: 10) == [first, second])
        #expect(try journal.read(limit: 1) == [second])
        #expect(try Journal(path: "/nonexistent/j.jsonl").read(limit: 5) == [])
    }
}
