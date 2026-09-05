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
        _ = try? shell.run("osascript", ["-e", script], cwd: nil)
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
