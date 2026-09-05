import Testing
@testable import DiskGCCore

@Suite struct ShellTests {
    @Test func processShellRunsCommand() throws {
        let result = try ProcessShell().run("/bin/echo", ["hi"], cwd: nil)
        #expect(result.status == 0)
        #expect(result.stdout == "hi\n")
    }

    @Test func processShellResolvesCommandFromPath() throws {
        let result = try ProcessShell().run("echo", ["via-path"], cwd: nil)
        #expect(result.stdout == "via-path\n")
    }

    @Test func processShellHonoursCwd() throws {
        let result = try ProcessShell().run("/bin/pwd", [], cwd: "/private/tmp")
        #expect(result.stdout == "/private/tmp\n")
    }

    @Test func fakeShellReturnsRecordedResultAndRecordsCalls() throws {
        let shell = FakeShell()
        shell.responses["git status"] = ShellResult(status: 0, stdout: "clean", stderr: "")
        let result = try shell.run("git", ["status"], cwd: nil)
        #expect(result.stdout == "clean")
        #expect(shell.calls == ["git status"])
    }

    @Test func fakeShellThrowsOnUnknownCommand() {
        let shell = FakeShell()
        #expect(throws: FakeShell.Error.self) {
            try shell.run("docker", ["ps"], cwd: nil)
        }
    }
}
