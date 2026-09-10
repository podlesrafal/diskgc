import Foundation

public struct ToolCacheScanner: DiskScanner {
    public let id = ScannerID.toolCaches

    public init() {}

    struct Entry {
        var name: String
        var path: String
        var action: Action
    }

    func entries(_ ctx: ScanContext) -> [Entry] {
        let home = ctx.home
        let pnpmStore = "\(home)/Library/pnpm/store"
        let goModCache = ctx.environment["GOMODCACHE"] ?? "\(home)/go/pkg/mod"
        return [
            Entry(name: "uv", path: "\(home)/.cache/uv", action: .removeContents(path: "\(home)/.cache/uv", root: home)),
            Entry(name: "yarn-berry", path: "\(home)/.yarn/berry/cache", action: .removeContents(path: "\(home)/.yarn/berry/cache", root: home)),
            Entry(name: "npm", path: "\(home)/.npm/_cacache", action: .removeContents(path: "\(home)/.npm/_cacache", root: home)),
            Entry(
                name: "pnpm", path: pnpmStore,
                action: prune(with: "pnpm", arguments: ["store", "prune"], orClear: pnpmStore, ctx: ctx)
            ),
            Entry(
                name: "go-mod", path: goModCache,
                action: prune(with: "go", arguments: ["clean", "-modcache"], orClear: goModCache, ctx: ctx)
            ),
        ]
    }

    func prune(with command: String, arguments: [String], orClear path: String, ctx: ScanContext) -> Action {
        guard ctx.hasCommand(command) else {
            return .removeContents(path: path, root: Self.parent(of: path))
        }
        return .run(command: command, arguments: arguments)
    }

    static func parent(of path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    public func scan(_ ctx: ScanContext) throws -> [Candidate] {
        entries(ctx).compactMap { entry in
            guard Walker.isRealDirectory(entry.path, fs: ctx.fs) else { return nil }
            return Candidate(
                scanner: id, tier: ctx.tier(id), group: "Tool caches", id: entry.path, label: entry.name,
                detail: ctx.display(entry.path), sizeBytes: ctx.size(of: entry.path),
                staleDays: ctx.days(since: Walker.newestEntryDate(in: entry.path, fs: ctx.fs)),
                actions: [entry.action]
            )
        }
    }
}
