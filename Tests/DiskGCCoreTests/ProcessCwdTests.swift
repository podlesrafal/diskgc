import Testing
@testable import DiskGCCore

@Suite struct ProcessCwdTests {
    @Test func parsesLsofOutput() throws {
        let shell = FakeShell()
        shell.respond("lsof", ["-w", "-n", "-F", "pn", "-d", "cwd"], stdout: "p1\nfcwd\nn/a/b\np2\nfcwd\nn/c\np3\nfcwd\nn/a/b\n")
        #expect(ProcessCwd.activeDirectories(shell: shell) == ["/a/b", "/c"])
    }

    @Test func toleratesLsofFailure() {
        #expect(ProcessCwd.activeDirectories(shell: FakeShell()) == [])
    }

    @Test func detectsUse() {
        #expect(ProcessCwd.isInUse("/a", active: ["/a/b"]))
        #expect(ProcessCwd.isInUse("/a", active: ["/a"]))
        #expect(!ProcessCwd.isInUse("/a", active: ["/ab"]))
        #expect(!ProcessCwd.isInUse("/a/b", active: ["/a"]))
    }
}
