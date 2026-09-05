import Foundation
import Testing
@testable import DiskGCCore

@Suite struct LaunchAgentTests {
    @Test func plistContainsSchedule() {
        let plist = LaunchAgent.plist(binary: "/Users/x/.local/bin/diskgc", logDir: "/Users/x/Library/Logs/diskgc", path: "/a:/b", intervalSeconds: 1800)
        #expect(plist.contains("<string>dev.rpo.diskgc</string>"))
        #expect(plist.contains("<string>tick</string>"))
        #expect(plist.contains("<integer>1800</integer>"))
        #expect(plist.contains("<string>/a:/b</string>"))
        #expect(plist.contains("<key>RunAtLoad</key>"))
        #expect(plist.contains("<string>Background</string>"))
    }

    @Test func installCopiesBinaryAndBootstraps() throws {
        let home = TestSupport.tempDir("home")
        let source = TestSupport.tempDir("src") + "/diskgc"
        TestSupport.touch(source, content: "#!/bin/sh\n")
        let shell = FakeShell()
        let plist = LaunchAgent.plistPath(home: home)
        shell.respond("launchctl", ["bootstrap", "gui/\(getuid())", plist], stdout: "")
        let written = try LaunchAgent.install(binarySource: source, home: home, logDir: "\(home)/Library/Logs/diskgc", path: "/x", shell: shell, fs: .default)
        #expect(written == plist)
        #expect(FileManager.default.fileExists(atPath: "\(home)/.local/bin/diskgc"))
        #expect(FileManager.default.fileExists(atPath: plist))
        #expect(shell.calls == ["launchctl bootout gui/\(getuid()) \(plist)", "launchctl bootstrap gui/\(getuid()) \(plist)"])
        try LaunchAgent.uninstall(home: home, shell: shell, fs: .default)
        #expect(!FileManager.default.fileExists(atPath: plist))
    }
}
