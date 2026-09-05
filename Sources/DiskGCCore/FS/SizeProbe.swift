import Foundation

public protocol SizeProbe {
    func sizeBytes(of path: String) throws -> Int64
}

public struct DuSizeProbe: SizeProbe {
    let shell: ShellRunner

    public init(shell: ShellRunner) {
        self.shell = shell
    }

    public func sizeBytes(of path: String) throws -> Int64 {
        let result = try shell.run("du", ["-sk", path], cwd: nil)
        let field = result.stdout.split(whereSeparator: { $0 == "\t" || $0 == " " }).first ?? ""
        guard let kilobytes = Int64(field) else { throw SizeProbeError.unparsable(result.stdout) }
        return kilobytes * 1024
    }
}

public enum SizeProbeError: Error, Equatable {
    case unparsable(String)
}

public struct SizeEntry: Codable, Equatable, Sendable {
    public var mtime: Double
    public var size: Int64
    public var at: Date

    public init(mtime: Double, size: Int64, at: Date) {
        self.mtime = mtime
        self.size = size
        self.at = at
    }
}

public final class CachingSizeProbe: SizeProbe {
    let inner: SizeProbe
    let maxAge: TimeInterval
    let fs: FileManager
    let now: () -> Date
    public private(set) var cache: [String: SizeEntry]

    public init(inner: SizeProbe, cache: [String: SizeEntry], maxAge: TimeInterval, fs: FileManager, now: @escaping () -> Date) {
        self.inner = inner
        self.cache = cache
        self.maxAge = maxAge
        self.fs = fs
        self.now = now
    }

    public func sizeBytes(of path: String) throws -> Int64 {
        let mtime = Walker.modificationDate(path, fs: fs)?.timeIntervalSince1970 ?? 0
        let current = now()
        if let entry = cache[path], entry.mtime == mtime, current.timeIntervalSince(entry.at) < maxAge {
            return entry.size
        }
        let size = try inner.sizeBytes(of: path)
        cache[path] = SizeEntry(mtime: mtime, size: size, at: current)
        return size
    }

    public func prune(keeping paths: Set<String>) {
        cache = cache.filter { paths.contains($0.key) }
    }
}
