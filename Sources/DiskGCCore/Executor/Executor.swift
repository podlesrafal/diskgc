import Foundation

public struct ExecutionResult: Equatable {
    public var candidate: Candidate
    public var ok: Bool
    public var message: String

    public init(candidate: Candidate, ok: Bool, message: String) {
        self.candidate = candidate
        self.ok = ok
        self.message = message
    }
}

public struct Executor {
    public let shell: ShellRunner
    public let fs: FileManager
    public let never: [String]
    public let journal: Journal
    public let dryRun: Bool
    let now: () -> Date

    public init(shell: ShellRunner, fs: FileManager, never: [String], journal: Journal, dryRun: Bool, now: @escaping () -> Date = Date.init) {
        self.shell = shell
        self.fs = fs
        self.never = never
        self.journal = journal
        self.dryRun = dryRun
        self.now = now
    }

    public func execute(_ candidate: Candidate) -> ExecutionResult {
        for action in candidate.actions {
            let description = Self.describe(action)
            if dryRun {
                record(candidate, description, dryRun: true, ok: true, error: nil)
                continue
            }
            record(candidate, description, dryRun: false, ok: false, error: "pending")
            do {
                try perform(action)
                record(candidate, description, dryRun: false, ok: true, error: nil)
            } catch {
                let message = Self.message(for: error)
                record(candidate, description, dryRun: false, ok: false, error: message)
                return ExecutionResult(candidate: candidate, ok: false, message: "\(description): \(message)")
            }
        }
        return ExecutionResult(candidate: candidate, ok: true, message: dryRun ? "dry-run" : "done")
    }

    public static func describe(_ action: Action) -> String {
        switch action {
        case .removeDirectory(let path, _): return "rm -rf \(path)"
        case .removeContents(let path, _): return "rm -rf \(path)/*"
        case .run(let command, let arguments): return ([command] + arguments).joined(separator: " ")
        case .worktreeRemove(let repo, let path): return "git -C \(repo) worktree remove \(path)"
        case .worktreePrune(let repo): return "git -C \(repo) worktree prune"
        }
    }

    func perform(_ action: Action) throws {
        switch action {
        case .removeDirectory(let path, let root):
            try PathSafety.validate(path, root: root, never: never, fs: fs)
            try fs.removeItem(atPath: path)
        case .removeContents(let path, let root):
            try PathSafety.validate(path, root: root, never: never, fs: fs)
            for entry in try fs.contentsOfDirectory(atPath: path) {
                try fs.removeItem(atPath: "\(path)/\(entry)")
            }
        case .run(let command, let arguments):
            try runChecked(command, arguments)
        case .worktreeRemove(let repo, let path):
            try runChecked("git", ["-C", repo, "worktree", "remove", path])
        case .worktreePrune(let repo):
            try runChecked("git", ["-C", repo, "worktree", "prune"])
        }
    }

    func runChecked(_ command: String, _ arguments: [String]) throws {
        let result = try shell.run(command, arguments, cwd: nil)
        guard result.succeeded else { throw ExecutorError.commandFailed(status: result.status, stderr: result.stderr) }
    }

    func record(_ candidate: Candidate, _ action: String, dryRun: Bool, ok: Bool, error: String?) {
        let entry = JournalEntry(
            at: now(), scanner: candidate.scanner, id: candidate.id, label: candidate.label,
            sizeBytes: candidate.sizeBytes, action: action, dryRun: dryRun, ok: ok, error: error
        )
        try? journal.append(entry)
    }

    static func message(for error: Error) -> String {
        switch error {
        case let safety as PathSafetyError: return "refused: \(safety)"
        case ExecutorError.commandFailed(let status, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "exit \(status)" + (detail.isEmpty ? "" : ": \(detail)")
        default: return String(describing: error)
        }
    }
}

public enum ExecutorError: Error, Equatable {
    case commandFailed(status: Int32, stderr: String)
}
