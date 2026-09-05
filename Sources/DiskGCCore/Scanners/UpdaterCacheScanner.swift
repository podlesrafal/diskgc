import Foundation

public struct UpdaterCacheScanner: Scanner {
    public let id = ScannerID.updaterCaches
    public static let minimumAgeDays = 7

    public init() {}

    public func scan(_ ctx: ScanContext) throws -> [Candidate] {
        let caches = "\(ctx.home)/Library/Caches"
        let support = "\(ctx.home)/Library/Application Support"
        var paths = Walker.subdirectories(of: caches, fs: ctx.fs).filter { path in
            let name = (path as NSString).lastPathComponent
            return name.contains("ShipIt") || name.hasSuffix("-updater")
        }.map { ($0, caches) }
        let dockerInstall = "\(support)/com.docker.install"
        if Walker.isRealDirectory(dockerInstall, fs: ctx.fs) { paths.append((dockerInstall, support)) }
        return paths.compactMap { path, root in
            let stale = ctx.days(since: Walker.newestEntryDate(in: path, fs: ctx.fs))
            guard stale >= Self.minimumAgeDays else { return nil }
            return Candidate(
                scanner: id, group: "Updater caches", id: path, label: (path as NSString).lastPathComponent,
                detail: ctx.display(path), sizeBytes: ctx.size(of: path), staleDays: stale,
                actions: [.removeDirectory(path: path, root: root)]
            )
        }
    }
}
