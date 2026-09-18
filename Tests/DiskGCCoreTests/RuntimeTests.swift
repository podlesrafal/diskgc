import Foundation
import Testing
@testable import DiskGCCore

@Suite struct RuntimeTests {
    @Test func resolvesEveryPathUnderTheGivenHome() throws {
        let home = TestSupport.tempDir("home")
        let runtime = try Runtime(home: home)
        #expect(runtime.configPath == "\(home)/.config/diskgc/config.yaml")
        #expect(runtime.statePath == "\(home)/.local/share/diskgc/state.json")
        #expect(runtime.journalPath == "\(home)/.local/share/diskgc/journal.jsonl")
        #expect(runtime.logDir == "\(home)/Library/Logs/diskgc")
    }

    @Test func readsTheConfigAndExpandsProjectRootsAgainstThatHome() throws {
        let home = TestSupport.tempDir("home")
        TestSupport.touch("\(home)/.config/diskgc/config.yaml", content: "target_free_gb: 42\nproject_roots:\n  - ~/Code\n")
        let runtime = try Runtime(home: home)
        #expect(runtime.config.targetFreeGB == 42)
        #expect(runtime.config.projectRoots == ["\(home)/Code"])
        #expect(runtime.targetBytes == 42 * ByteFormat.gigabyte)
    }

    @Test func savesTheSizeCacheItScannedWith() throws {
        let home = TestSupport.tempDir("home")
        let runtime = try Runtime(home: home)
        let probe = runtime.sizeProbe(rescan: false)
        let file = "\(home)/payload"
        TestSupport.touch(file, content: String(repeating: "x", count: 4096))
        _ = try probe.sizeBytes(of: file)
        try runtime.save(runtime.state, sizes: probe)
        #expect(State.load(from: runtime.statePath).sizes[file] != nil)
    }
}
