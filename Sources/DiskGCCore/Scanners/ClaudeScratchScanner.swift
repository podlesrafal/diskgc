import Foundation

public struct ClaudeScratchScanner: Scanner {
    public let id = ScannerID.claudeScratch

    public init() {}

    public func scan(_ ctx: ScanContext) throws -> [Candidate] {
        Walker.subdirectories(of: ctx.tmpRoot, fs: ctx.fs).flatMap { project in
            Walker.subdirectories(of: project, fs: ctx.fs).compactMap { session in
                candidate(for: session, project: project, ctx: ctx)
            }
        }
    }

    func candidate(for session: String, project: String, ctx: ScanContext) -> Candidate? {
        let stale = ctx.days(since: Walker.newestEntryDate(in: session, fs: ctx.fs))
        guard stale >= ctx.config.inactiveDays.claudeScratch, !ctx.isInUse(session) else { return nil }
        var repos: [String] = []
        for worktree in Self.worktrees(in: session, fs: ctx.fs) {
            guard ctx.git.isClean(worktree.path) else { return nil }
            repos.append(worktree.repo)
        }
        let label = (project as NSString).lastPathComponent + "/" + (session as NSString).lastPathComponent
        var actions: [Action] = [.removeDirectory(path: session, root: ctx.tmpRoot)]
        for repo in Set(repos).sorted() { actions.append(.worktreePrune(repo: repo)) }
        return Candidate(
            scanner: id, group: "Claude scratchpads", id: session, label: label,
            detail: repos.isEmpty ? nil : "worktree of \(Set(repos).sorted().map(ctx.display).joined(separator: ", "))",
            sizeBytes: ctx.size(of: session), staleDays: stale, actions: actions
        )
    }

    static func worktrees(in session: String, fs: FileManager, depth: Int = 0) -> [(path: String, repo: String)] {
        guard depth <= 3 else { return [] }
        var found: [(String, String)] = []
        for entry in (try? fs.contentsOfDirectory(atPath: session)) ?? [] {
            let path = "\(session)/\(entry)"
            if entry == ".git", let repo = repository(fromGitFile: path, fs: fs) {
                found.append((session, repo))
            } else if Walker.isRealDirectory(path, fs: fs), entry != "node_modules" {
                found += worktrees(in: path, fs: fs, depth: depth + 1)
            }
        }
        return found
    }

    static func repository(fromGitFile path: String, fs: FileManager) -> String? {
        guard let data = fs.contents(atPath: path) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("gitdir:") else { return nil }
        let gitdir = text.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard let range = gitdir.range(of: "/.git/worktrees/") else { return nil }
        return String(gitdir[..<range.lowerBound])
    }
}
