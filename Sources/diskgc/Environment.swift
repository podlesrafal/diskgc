import Foundation
import DiskGCCore

struct Environment {
    let home: String
    let configPath: String
    let statePath: String
    let journalPath: String
    let logDir: String
    let config: Config
    let state: State
    let shell = ProcessShell()
    let journal: Journal

    init() throws {
        home = FileManager.default.homeDirectoryForCurrentUser.path
        configPath = "\(home)/.config/diskgc/config.yaml"
        statePath = "\(home)/.local/share/diskgc/state.json"
        journalPath = "\(home)/.local/share/diskgc/journal.jsonl"
        logDir = "\(home)/Library/Logs/diskgc"
        config = try Config.load(from: configPath, home: home)
        state = State.load(from: statePath)
        journal = Journal(path: journalPath)
    }

    func sizeProbe(rescan: Bool) -> CachingSizeProbe {
        CachingSizeProbe(
            inner: DuSizeProbe(shell: shell), cache: rescan ? [:] : state.sizes,
            maxAge: Double(config.rescanHours) * 3600, fs: .default, now: Date.init
        )
    }

    func context(sizes: SizeProbe) -> ScanContext {
        ScanContext(
            config: config, shell: shell, sizes: sizes, home: home,
            activeCwds: ProcessCwd.activeDirectories(shell: shell), state: state
        )
    }

    func executor(dryRun: Bool) -> Executor {
        Executor(shell: shell, fs: .default, never: config.never, journal: journal, dryRun: dryRun)
    }

    func freeBytes() throws -> Int64 {
        try DiskSpace.freeBytes(at: home)
    }

    var targetBytes: Int64 {
        Int64(config.targetFreeGB) * ByteFormat.gigabyte
    }

    func save(_ state: State, sizes: CachingSizeProbe) throws {
        var updated = state
        updated.sizes = sizes.cache
        try updated.save(to: statePath)
    }
}
