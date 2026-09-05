import Foundation

public struct JetBrainsScanner: DiskScanner {
    public let id = ScannerID.jetbrains

    public init() {}

    public func scan(_ ctx: ScanContext) throws -> [Candidate] {
        let roots = ["\(ctx.home)/Library/Caches/JetBrains", "\(ctx.home)/Library/Logs/JetBrains"]
        return roots.flatMap { root in
            Walker.subdirectories(of: root, fs: ctx.fs).compactMap { path in
                let stale = ctx.days(since: Walker.newestEntryDate(in: path, fs: ctx.fs))
                guard stale >= ctx.config.inactiveDays.jetbrains else { return nil }
                return Candidate(
                    scanner: id, tier: ctx.tier(id), group: "JetBrains", id: path, label: (path as NSString).lastPathComponent,
                    detail: ctx.display(path), sizeBytes: ctx.size(of: path), staleDays: stale,
                    actions: [.removeDirectory(path: path, root: root)]
                )
            }
        }
    }
}
