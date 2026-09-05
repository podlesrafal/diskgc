import Foundation

public struct ToolCacheScanner: Scanner {
    public let id = ScannerID.toolCaches

    public init() {}

    struct Entry {
        var name: String
        var path: String
        var action: Action
    }

    func entries(_ ctx: ScanContext) -> [Entry] {
        let home = ctx.home
        let goModCache = ctx.environment["GOMODCACHE"] ?? "\(home)/go/pkg/mod"
        return [
            Entry(name: "uv", path: "\(home)/.cache/uv", action: .removeContents(path: "\(home)/.cache/uv", root: home)),
            Entry(name: "yarn-berry", path: "\(home)/.yarn/berry/cache", action: .removeContents(path: "\(home)/.yarn/berry/cache", root: home)),
            Entry(name: "npm", path: "\(home)/.npm/_cacache", action: .removeContents(path: "\(home)/.npm/_cacache", root: home)),
            Entry(name: "pnpm", path: "\(home)/Library/pnpm/store", action: .run(command: "pnpm", arguments: ["store", "prune"])),
            Entry(name: "go-mod", path: goModCache, action: .run(command: "go", arguments: ["clean", "-modcache"])),
        ]
    }

    public func scan(_ ctx: ScanContext) throws -> [Candidate] {
        entries(ctx).compactMap { entry in
            guard Walker.isRealDirectory(entry.path, fs: ctx.fs) else { return nil }
            return Candidate(
                scanner: id, group: "Tool caches", id: entry.path, label: entry.name,
                detail: ctx.display(entry.path), sizeBytes: ctx.size(of: entry.path),
                staleDays: ctx.days(since: Walker.newestEntryDate(in: entry.path, fs: ctx.fs)),
                actions: [entry.action]
            )
        }
    }
}
