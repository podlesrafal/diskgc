import Foundation

public enum ProcessCwd {
    public static func activeDirectories(shell: ShellRunner) -> [String] {
        guard let result = try? shell.run("lsof", ["-w", "-n", "-F", "pn", "-d", "cwd"], cwd: nil) else { return [] }
        var seen = Set<String>()
        var directories: [String] = []
        for line in result.stdout.split(separator: "\n") where line.hasPrefix("n") {
            let path = String(line.dropFirst())
            if seen.insert(path).inserted { directories.append(path) }
        }
        return directories
    }

    public static func isInUse(_ tree: String, active: [String]) -> Bool {
        active.contains { $0 == tree || PathSafety.isInside($0, tree) }
    }
}
