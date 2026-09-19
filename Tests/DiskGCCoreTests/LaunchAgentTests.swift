import Foundation
import Testing
@testable import DiskGCCore

@Suite struct LaunchAgentTests {
    @Test func plistLaunchesTheAppAndKeepsItAlive() {
        let binary = "/Users/x/Applications/DiskGC.app/Contents/MacOS/DiskGCBar"
        let plist = LaunchAgent.plist(binary: binary, logDir: "/Users/x/Library/Logs/diskgc", path: "/a:/b")
        #expect(plist.contains("<string>dev.rpo.diskgc</string>"))
        #expect(plist.contains("<string>\(binary)</string>"))
        #expect(plist.contains("<key>RunAtLoad</key>"))
        #expect(plist.contains("<key>KeepAlive</key>"))
        #expect(plist.contains("<key>ThrottleInterval</key>"))
        #expect(plist.contains("<string>/a:/b</string>"))
    }

    @Test func plistNoLongerSchedulesTheCliTick() {
        let plist = LaunchAgent.plist(binary: "/Users/x/Applications/DiskGC.app/Contents/MacOS/DiskGCBar", logDir: "/l", path: "/a")
        #expect(!plist.contains("<string>tick</string>"))
        #expect(!plist.contains("<key>StartInterval</key>"))
    }

    @Test func findsTheBundleBesideTheBinary() throws {
        let root = TestSupport.tempDir("build")
        TestSupport.touch("\(root)/diskgc", content: "")
        TestSupport.mkdir("\(root)/DiskGC.app")
        #expect(LaunchAgent.bundledApp(near: "\(root)/diskgc", fs: .default) == "\(root)/DiskGC.app")
    }

    @Test func findsTheBundleWhenSwiftpmResolvedTheBinaryIntoItsArchDirectory() throws {
        let root = TestSupport.tempDir("build")
        TestSupport.touch("\(root)/arm64-apple-macosx/release/diskgc", content: "")
        TestSupport.mkdir("\(root)/DiskGC.app")
        #expect(LaunchAgent.bundledApp(near: "\(root)/arm64-apple-macosx/release/diskgc", fs: .default) == "\(root)/DiskGC.app")
    }

    @Test func reportsNoBundleWhenNoneWasBuilt() throws {
        let root = TestSupport.tempDir("build")
        TestSupport.touch("\(root)/release/diskgc", content: "")
        #expect(LaunchAgent.bundledApp(near: "\(root)/release/diskgc", fs: .default) == nil)
    }

    @Test func installCopiesTheCliAndTheAppThenBootstraps() throws {
        let home = TestSupport.tempDir("home")
        let source = TestSupport.tempDir("src") + "/diskgc"
        TestSupport.touch(source, content: "#!/bin/sh\n")
        let appSource = TestSupport.tempDir("bundle") + "/DiskGC.app"
        TestSupport.touch("\(appSource)/Contents/MacOS/DiskGCBar", content: "#!/bin/sh\n")
        let shell = FakeShell()
        let plist = LaunchAgent.plistPath(home: home)
        shell.respond("launchctl", ["bootstrap", "gui/\(getuid())", plist], stdout: "")

        let written = try LaunchAgent.install(
            binarySource: source, appSource: appSource, home: home,
            logDir: "\(home)/Library/Logs/diskgc", path: "/x", shell: shell, fs: .default
        )

        #expect(written == plist)
        #expect(FileManager.default.fileExists(atPath: "\(home)/.local/bin/diskgc"))
        #expect(FileManager.default.fileExists(atPath: LaunchAgent.appBinaryPath(home: home)))
        #expect(try String(contentsOfFile: plist, encoding: .utf8).contains(LaunchAgent.appBinaryPath(home: home)))
        #expect(shell.calls == ["launchctl bootout gui/\(getuid()) \(plist)", "launchctl bootstrap gui/\(getuid()) \(plist)"])
    }

    @Test func installReplacesAnAppBundleLeftByAnEarlierInstall() throws {
        let home = TestSupport.tempDir("home")
        let source = TestSupport.tempDir("src") + "/diskgc"
        TestSupport.touch(source, content: "#!/bin/sh\n")
        let appSource = TestSupport.tempDir("bundle") + "/DiskGC.app"
        TestSupport.touch("\(appSource)/Contents/MacOS/DiskGCBar", content: "new\n")
        TestSupport.touch(LaunchAgent.appPath(home: home) + "/Contents/MacOS/DiskGCBar", content: "old\n")
        TestSupport.touch(LaunchAgent.appPath(home: home) + "/Contents/stale.txt", content: "leftover\n")
        let shell = FakeShell()
        shell.respond("launchctl", ["bootstrap", "gui/\(getuid())", LaunchAgent.plistPath(home: home)], stdout: "")

        try LaunchAgent.install(
            binarySource: source, appSource: appSource, home: home,
            logDir: "\(home)/Library/Logs/diskgc", path: "/x", shell: shell, fs: .default
        )

        #expect(try String(contentsOfFile: LaunchAgent.appBinaryPath(home: home), encoding: .utf8) == "new\n")
        #expect(!FileManager.default.fileExists(atPath: LaunchAgent.appPath(home: home) + "/Contents/stale.txt"))
    }

    @Test func uninstallRemovesThePlistAndTheAppBundle() throws {
        let home = TestSupport.tempDir("home")
        TestSupport.touch(LaunchAgent.plistPath(home: home), content: "<plist/>")
        TestSupport.touch(LaunchAgent.appBinaryPath(home: home), content: "#!/bin/sh\n")
        let shell = FakeShell()

        try LaunchAgent.uninstall(home: home, shell: shell, fs: .default)

        #expect(!FileManager.default.fileExists(atPath: LaunchAgent.plistPath(home: home)))
        #expect(!FileManager.default.fileExists(atPath: LaunchAgent.appPath(home: home)))
    }
}
