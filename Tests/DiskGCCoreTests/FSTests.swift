import Foundation
import Testing
@testable import DiskGCCore

@Suite struct FSTests {
    let fs = FileManager.default

    @Test func diskSpaceReportsPositiveFreeBytes() throws {
        #expect(try DiskSpace.freeBytes(at: NSHomeDirectory()) > 0)
    }

    @Test func walkerFindsNamedDirectoriesWithoutDescending() {
        let root = TestSupport.tempDir()
        TestSupport.mkdir("\(root)/a/node_modules/x/node_modules")
        TestSupport.mkdir("\(root)/b/c/target")
        TestSupport.mkdir("\(root)/.git/node_modules")
        TestSupport.mkdir("\(root)/deep/1/2/3/4/5/6/7/node_modules")
        let found = Walker.directories(named: ["node_modules", "target"], under: root, maxDepth: 6, skipping: [".git"], fs: fs)
        #expect(Set(found) == ["\(root)/a/node_modules", "\(root)/b/c/target"])
    }

    @Test func walkerNewestEntryDateConsidersTopLevelEntries() {
        let root = TestSupport.tempDir()
        TestSupport.touch("\(root)/old.txt")
        TestSupport.setModificationDate("\(root)/old.txt", daysAgo: 40)
        TestSupport.setModificationDate(root, daysAgo: 40)
        let oldDate = Walker.newestEntryDate(in: root, fs: fs)!
        #expect(Staleness.days(since: oldDate, now: Date()) == 40)
        TestSupport.touch("\(root)/fresh.txt")
        TestSupport.setModificationDate(root, daysAgo: 40)
        let fresh = Walker.newestEntryDate(in: root, fs: fs)!
        #expect(Staleness.days(since: fresh, now: Date()) == 0)
    }

    @Test func pathSafetyAcceptsRegularDirectoryUnderRoot() throws {
        let root = TestSupport.tempDir()
        TestSupport.mkdir("\(root)/proj/node_modules")
        try PathSafety.validate("\(root)/proj/node_modules", root: root, never: [], fs: fs)
    }

    @Test func pathSafetyRejectsEveryUnsafeCase() throws {
        let root = TestSupport.tempDir()
        TestSupport.mkdir("\(root)/proj/real")
        TestSupport.touch("\(root)/proj/file.txt")
        try fs.createSymbolicLink(atPath: "\(root)/proj/link", withDestinationPath: "\(root)/proj/real")
        let other = TestSupport.tempDir("other")

        #expect(throws: PathSafetyError.notAbsolute) { try PathSafety.validate("relative/path", root: root, never: [], fs: fs) }
        #expect(throws: PathSafetyError.symlink) { try PathSafety.validate("\(root)/proj/link", root: root, never: [], fs: fs) }
        #expect(throws: PathSafetyError.notDirectory) { try PathSafety.validate("\(root)/proj/file.txt", root: root, never: [], fs: fs) }
        #expect(throws: PathSafetyError.notDirectory) { try PathSafety.validate("\(root)/proj/missing", root: root, never: [], fs: fs) }
        #expect(throws: PathSafetyError.tooShallow) { try PathSafety.validate("/private/tmp", root: "/private", never: [], fs: fs) }
        #expect(throws: PathSafetyError.outsideRoot) { try PathSafety.validate("\(other)", root: root, never: [], fs: fs) }
        #expect(throws: PathSafetyError.equalsRoot) { try PathSafety.validate(root, root: root, never: [], fs: fs) }
        #expect(throws: PathSafetyError.underNever) { try PathSafety.validate("\(root)/proj/real", root: root, never: ["\(root)/proj"], fs: fs) }
        #expect(throws: PathSafetyError.underNever) { try PathSafety.validate("\(root)/proj/real", root: root, never: ["\(root)/proj/real"], fs: fs) }
        #expect(throws: PathSafetyError.outsideRoot) { try PathSafety.validate("\(root)/proj/../../\(other.split(separator: "/").last!)", root: root, never: [], fs: fs) }
    }

    @Test func duSizeProbeParsesKilobytes() throws {
        let shell = FakeShell()
        shell.respond("du", ["-sk", "/p"], stdout: "4096\t/p\n")
        #expect(try DuSizeProbe(shell: shell).sizeBytes(of: "/p") == 4_194_304)
    }

    @Test func cachingSizeProbeReusesUntilMtimeChanges() throws {
        let root = TestSupport.tempDir()
        let dir = "\(root)/d"
        TestSupport.mkdir(dir)
        let shell = FakeShell()
        shell.respond("du", ["-sk", dir], stdout: "10\t\(dir)\n")
        let probe = CachingSizeProbe(inner: DuSizeProbe(shell: shell), cache: [:], maxAge: 3600, fs: FileManager.default, now: { Date() })
        #expect(try probe.sizeBytes(of: dir) == 10_240)
        #expect(try probe.sizeBytes(of: dir) == 10_240)
        #expect(shell.calls.count == 1)
        TestSupport.setModificationDate(dir, daysAgo: 1)
        #expect(try probe.sizeBytes(of: dir) == 10_240)
        #expect(shell.calls.count == 2)
        #expect(probe.cache[dir]?.size == 10_240)
    }

    @Test func cachingSizeProbeExpiresByAge() throws {
        let root = TestSupport.tempDir()
        let dir = "\(root)/d"
        TestSupport.mkdir(dir)
        let shell = FakeShell()
        shell.respond("du", ["-sk", dir], stdout: "10\t\(dir)\n")
        var clock = Date()
        let probe = CachingSizeProbe(inner: DuSizeProbe(shell: shell), cache: [:], maxAge: 60, fs: FileManager.default, now: { clock })
        _ = try probe.sizeBytes(of: dir)
        clock = clock.addingTimeInterval(120)
        _ = try probe.sizeBytes(of: dir)
        #expect(shell.calls.count == 2)
    }

    @Test func stalenessDays() {
        let now = Date()
        #expect(Staleness.days(since: now.addingTimeInterval(-3 * 86_400 - 60), now: now) == 3)
        #expect(Staleness.days(since: now.addingTimeInterval(3600), now: now) == 0)
        #expect(Staleness.days(since: nil, now: now) == 0)
    }
}
