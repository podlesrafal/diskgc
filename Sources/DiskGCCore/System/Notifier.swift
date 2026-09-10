import Foundation

public protocol Notifier {
    func notify(title: String, message: String)
}

public struct OSAScriptNotifier: Notifier {
    let shell: ShellRunner

    public init(shell: ShellRunner) {
        self.shell = shell
    }

    public func notify(title: String, message: String) {
        let script = "display notification \"\(Self.escape(message))\" with title \"\(Self.escape(title))\""
        let result = try? shell.run("osascript", ["-e", script], cwd: nil)
        guard result?.succeeded != true else { return }
        let detail = result.map { $0.stderr.trimmingCharacters(in: .whitespacesAndNewlines) } ?? "osascript not found"
        FileHandle.standardError.write(Data("notification failed (\(detail)): \(title): \(message)\n".utf8))
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

public struct PrintingNotifier: Notifier {
    let output: (String) -> Void

    public init(output: @escaping (String) -> Void) {
        self.output = output
    }

    public func notify(title: String, message: String) {
        output("[notification] \(title): \(message)")
    }
}
