import Foundation

public struct ScanContext {
    public var config: Config
    public var shell: ShellRunner
    public var sizes: SizeProbe
    public var fs: FileManager
    public var now: Date
    public var home: String
    public var activeCwds: [String]
    public var git: GitProbe
    public var state: State
    public var tmpRoot: String
    public var environment: [String: String]

    public init(
        config: Config, shell: ShellRunner, sizes: SizeProbe, fs: FileManager = .default, now: Date = Date(),
        home: String, activeCwds: [String] = [], git: GitProbe? = nil, state: State = State(),
        tmpRoot: String = "/private/tmp/claude-\(getuid())", environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.config = config
        self.shell = shell
        self.sizes = sizes
        self.fs = fs
        self.now = now
        self.home = home
        self.activeCwds = activeCwds
        self.git = git ?? GitProbe(shell: shell, fs: fs)
        self.state = state
        self.tmpRoot = tmpRoot
        self.environment = environment
    }

    public func tier(_ id: ScannerID) -> Tier {
        config.tier(of: id)
    }

    public func size(of path: String) -> Int64 {
        (try? sizes.sizeBytes(of: path)) ?? 0
    }

    public func days(since date: Date?) -> Int {
        Staleness.days(since: date, now: now)
    }

    public func hasCommand(_ command: String) -> Bool {
        shell.locate(command) != nil
    }

    public func isInUse(_ tree: String) -> Bool {
        ProcessCwd.isInUse(tree, active: activeCwds)
    }

    public func display(_ path: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

public protocol DiskScanner {
    var id: ScannerID { get }
    func scan(_ ctx: ScanContext) throws -> [Candidate]
}
