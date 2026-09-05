import Foundation

public struct ShellResult: Equatable, Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { status == 0 }
}

public protocol ShellRunner {
    func run(_ command: String, _ arguments: [String], cwd: String?) throws -> ShellResult
}

public extension ShellRunner {
    func run(_ command: String, _ arguments: [String]) throws -> ShellResult {
        try run(command, arguments, cwd: nil)
    }
}
