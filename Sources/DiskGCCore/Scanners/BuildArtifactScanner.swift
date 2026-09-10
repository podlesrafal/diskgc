import Foundation

public struct BuildArtifactScanner: DiskScanner {
    public let id = ScannerID.buildArtifacts
    public static let names: Set<String> = [
        "node_modules", "target", ".angular", ".nx", "dist", "build", ".next", ".gradle", ".turbo", ".parcel-cache",
        ".svelte-kit", "out", ".venv", "venv", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
        ".terraform", "Pods", ".dart_tool", "coverage",
    ]
    public static let maxDepth = 12

    public init() {}

    public func scan(_ ctx: ScanContext) throws -> [Candidate] {
        var result: [Candidate] = []
        for root in ctx.config.projectRoots where Walker.isRealDirectory(root, fs: ctx.fs) {
            try Walker.checkReadable(root)
            let found = Walker.directories(named: Self.names, under: root, maxDepth: Self.maxDepth, skipping: [".git"], fs: ctx.fs)
            result += candidates(for: found, root: root, ctx: ctx)
        }
        return result
    }

    func candidates(for paths: [String], root: String, ctx: ScanContext) -> [Candidate] {
        var pathsByTree: [String: [String]] = [:]
        for path in paths {
            guard let tree = Walker.workTree(containing: (path as NSString).deletingLastPathComponent) else { continue }
            pathsByTree[tree, default: []].append(path)
        }
        var result: [Candidate] = []
        let threshold = ctx.config.inactiveDays.buildArtifacts
        for (tree, treePaths) in pathsByTree.sorted(by: { $0.key < $1.key }) {
            guard !ctx.isInUse(tree) else { continue }
            let repoIdle = ctx.days(since: ctx.git.indexModificationDate(of: tree))
            let ignored = ctx.git.ignoredPaths(treePaths, in: tree)
            for path in treePaths where ignored.contains(path) {
                let builtDaysAgo = ctx.days(since: Walker.newestEntryDate(in: path, fs: ctx.fs))
                guard builtDaysAgo >= threshold else { continue }
                result.append(Candidate(
                    scanner: id, tier: repoIdle >= threshold ? ctx.tier(id) : .ask, group: "Build artifacts",
                    id: path, label: ctx.display(path),
                    detail: "built \(builtDaysAgo)d ago, \((tree as NSString).lastPathComponent) idle \(repoIdle)d",
                    sizeBytes: ctx.size(of: path), staleDays: builtDaysAgo,
                    actions: [.removeDirectory(path: path, root: root)]
                ))
            }
        }
        return result
    }
}
