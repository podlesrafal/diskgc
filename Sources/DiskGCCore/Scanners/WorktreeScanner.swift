import Foundation

public struct WorktreeScanner: DiskScanner {
    public let id = ScannerID.worktrees
    public static let repoSearchDepth = 5

    public init() {}

    public func scan(_ ctx: ScanContext) throws -> [Candidate] {
        var candidates: [Candidate] = []
        for root in ctx.config.projectRoots where Walker.isRealDirectory(root, fs: ctx.fs) {
            for repo in Self.repositories(under: root, depth: 0, fs: ctx.fs) {
                candidates += scan(repo: repo, ctx: ctx)
            }
        }
        return candidates
    }

    static func repositories(under dir: String, depth: Int, fs: FileManager) -> [String] {
        guard depth < repoSearchDepth else { return [] }
        var repos: [String] = []
        for path in Walker.subdirectories(of: dir, fs: fs) {
            let name = (path as NSString).lastPathComponent
            guard name != "node_modules", name != ".git" else { continue }
            if Walker.isRealDirectory("\(path)/.git", fs: fs) {
                repos.append(path)
            } else {
                repos += repositories(under: path, depth: depth + 1, fs: fs)
            }
        }
        return repos
    }

    func scan(repo: String, ctx: ScanContext) -> [Candidate] {
        let entries = ctx.git.worktrees(of: repo).filter { !$0.isMain }
        var candidates: [Candidate] = []
        if entries.contains(where: \.prunable) {
            let gone = entries.filter(\.prunable).map { ctx.display($0.path) }
            candidates.append(Candidate(
                scanner: id, tier: .auto, group: "Worktrees (prune)", id: "prune:\(repo)", label: ctx.display(repo),
                detail: "stale registrations: \(gone.joined(separator: ", "))", sizeBytes: 0, staleDays: 0,
                actions: [.worktreePrune(repo: repo)]
            ))
        }
        for entry in entries where !entry.prunable {
            guard let candidate = candidate(for: entry, repo: repo, ctx: ctx) else { continue }
            candidates.append(candidate)
        }
        return candidates
    }

    func candidate(for entry: WorktreeEntry, repo: String, ctx: ScanContext) -> Candidate? {
        guard !ctx.state.keptWorktrees.contains(entry.path),
              Walker.isRealDirectory(entry.path, fs: ctx.fs),
              !ctx.isInUse(entry.path) else { return nil }
        let stale = ctx.days(since: ctx.git.indexModificationDate(of: entry.path))
        guard stale >= ctx.config.inactiveDays.worktree, ctx.git.isClean(entry.path) else { return nil }
        let ref = entry.branch.map { "branch \($0)" } ?? "detached"
        return Candidate(
            scanner: id, tier: ctx.tier(id), group: "Worktrees", id: entry.path, label: ctx.display(entry.path),
            detail: "\(ref), \(stale)d idle, repo \(ctx.display(repo))", sizeBytes: ctx.size(of: entry.path), staleDays: stale,
            actions: [.worktreeRemove(repo: repo, path: entry.path)]
        )
    }
}
