import Foundation

public struct BuildArtifactScanner: DiskScanner {
    public let id = ScannerID.buildArtifacts
    public static let names: Set<String> = ["node_modules", "target", ".angular", ".nx", "dist", "build", ".next", ".gradle"]
    public static let maxDepth = 12

    public init() {}

    public func scan(_ ctx: ScanContext) throws -> [Candidate] {
        var result: [Candidate] = []
        for root in ctx.config.projectRoots where Walker.isRealDirectory(root, fs: ctx.fs) {
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
        for (tree, treePaths) in pathsByTree.sorted(by: { $0.key < $1.key }) {
            let stale = ctx.days(since: ctx.git.indexModificationDate(of: tree))
            guard stale >= ctx.config.inactiveDays.buildArtifacts, !ctx.isInUse(tree) else { continue }
            let ignored = ctx.git.ignoredPaths(treePaths, in: tree)
            for path in treePaths where ignored.contains(path) {
                result.append(Candidate(
                    scanner: id, tier: ctx.tier(id), group: "Build artifacts", id: path, label: ctx.display(path),
                    detail: "\((tree as NSString).lastPathComponent) idle \(stale)d",
                    sizeBytes: ctx.size(of: path), staleDays: stale,
                    actions: [.removeDirectory(path: path, root: root)]
                ))
            }
        }
        return result
    }
}
