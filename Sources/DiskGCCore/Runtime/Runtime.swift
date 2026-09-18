import Foundation

public struct Runtime {
    public let home: String
    public let configPath: String
    public let statePath: String
    public let journalPath: String
    public let logDir: String
    public let config: Config
    public let state: State
    public let shell = ProcessShell()
    public let journal: Journal

    public init(home: String = FileManager.default.homeDirectoryForCurrentUser.path) throws {
        self.home = home
        configPath = "\(home)/.config/diskgc/config.yaml"
        statePath = "\(home)/.local/share/diskgc/state.json"
        journalPath = "\(home)/.local/share/diskgc/journal.jsonl"
        logDir = "\(home)/Library/Logs/diskgc"
        config = try Config.load(from: configPath, home: home)
        state = State.load(from: statePath)
        journal = Journal(path: journalPath)
    }

    public func sizeProbe(rescan: Bool) -> CachingSizeProbe {
        CachingSizeProbe(
            inner: DuSizeProbe(shell: shell), cache: rescan ? [:] : state.sizes,
            maxAge: Double(config.rescanHours) * 3600, fs: .default, now: Date.init
        )
    }

    public func context(sizes: SizeProbe) -> ScanContext {
        ScanContext(
            config: config, shell: shell, sizes: sizes, home: home,
            activeCwds: ProcessCwd.activeDirectories(shell: shell), state: state
        )
    }

    public func executor(dryRun: Bool) -> Executor {
        Executor(shell: shell, fs: .default, never: config.never, journal: journal, dryRun: dryRun)
    }

    public func freeBytes() throws -> Int64 {
        try DiskSpace.freeBytes(at: home)
    }

    public var targetBytes: Int64 {
        Int64(config.targetFreeGB) * ByteFormat.gigabyte
    }

    public func save(_ state: State, sizes: CachingSizeProbe) throws {
        var updated = state
        updated.sizes = sizes.cache
        try updated.save(to: statePath)
    }
}
