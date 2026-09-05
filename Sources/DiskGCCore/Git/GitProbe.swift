import Foundation

public struct WorktreeEntry: Equatable, Sendable {
    public var path: String
    public var head: String
    public var branch: String?
    public var detached: Bool
    public var prunable: Bool
    public var isMain: Bool

    public init(path: String, head: String, branch: String?, detached: Bool, prunable: Bool, isMain: Bool) {
        self.path = path
        self.head = head
        self.branch = branch
        self.detached = detached
        self.prunable = prunable
        self.isMain = isMain
    }
}

public struct GitProbe {
    let shell: ShellRunner
    let fs: FileManager

    public init(shell: ShellRunner, fs: FileManager) {
        self.shell = shell
        self.fs = fs
    }

    public func toplevel(of path: String) -> String? {
        output(["-C", path, "rev-parse", "--show-toplevel"])
    }

    public func gitDir(of path: String) -> String? {
        output(["-C", path, "rev-parse", "--absolute-git-dir"])
    }

    public func isIgnored(_ path: String, in worktree: String) -> Bool {
        (try? shell.run("git", ["-C", worktree, "check-ignore", "-q", path], cwd: nil))?.status == 0
    }

    public func isClean(_ worktree: String) -> Bool {
        guard let result = try? shell.run("git", ["-C", worktree, "status", "--porcelain"], cwd: nil), result.succeeded else { return false }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func worktrees(of repo: String) -> [WorktreeEntry] {
        guard let porcelain = output(["-C", repo, "worktree", "list", "--porcelain"], trim: false) else { return [] }
        return Self.parseWorktreeList(porcelain)
    }

    public func indexModificationDate(of worktree: String) -> Date? {
        guard let dir = Self.localGitDir(of: worktree, fs: fs) ?? gitDir(of: worktree) else { return nil }
        return Walker.modificationDate("\(dir)/index", fs: fs) ?? Walker.modificationDate(dir, fs: fs)
    }

    public static func localGitDir(of worktree: String, fs: FileManager) -> String? {
        let dotGit = "\(worktree)/.git"
        if Walker.isRealDirectory(dotGit, fs: fs) { return dotGit }
        guard let data = fs.contents(atPath: dotGit) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("gitdir:") else { return nil }
        let target = text.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return target.hasPrefix("/") ? target : PathSafety.normalize("\(worktree)/\(target)")
    }

    public static func parseWorktreeList(_ porcelain: String) -> [WorktreeEntry] {
        var entries: [WorktreeEntry] = []
        var current: WorktreeEntry?
        func flush() {
            if let entry = current { entries.append(entry) }
            current = nil
        }
        for rawLine in porcelain.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.isEmpty { flush(); continue }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let key = parts[0]
            let value = parts.count > 1 ? parts[1] : ""
            switch key {
            case "worktree":
                flush()
                current = WorktreeEntry(path: value, head: "", branch: nil, detached: false, prunable: false, isMain: entries.isEmpty)
            case "HEAD": current?.head = value
            case "branch": current?.branch = value.hasPrefix("refs/heads/") ? String(value.dropFirst("refs/heads/".count)) : value
            case "detached": current?.detached = true
            case "prunable": current?.prunable = true
            default: break
            }
        }
        flush()
        return entries
    }

    func output(_ arguments: [String], trim: Bool = true) -> String? {
        guard let result = try? shell.run("git", arguments, cwd: nil), result.succeeded else { return nil }
        return trim ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : result.stdout
    }
}

public extension GitProbe {
    func ignoredPaths(_ paths: [String], in worktree: String) -> Set<String> {
        guard !paths.isEmpty,
              let result = try? shell.run("git", ["-C", worktree, "check-ignore", "--no-index"] + paths, cwd: nil),
              result.status == 0 || result.status == 1 else { return [] }
        return Set(result.stdout.split(separator: "\n").map(String.init))
    }
}
