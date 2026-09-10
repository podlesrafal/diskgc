import Foundation

public final class FakeShell: ShellRunner {
    public enum Error: Swift.Error, Equatable {
        case unexpected(String)
    }

    public var responses: [String: ShellResult] = [:]
    public var executables: Set<String> = []
    public private(set) var calls: [String] = []

    public init() {}

    public static func key(_ command: String, _ arguments: [String]) -> String {
        ([command] + arguments).joined(separator: " ")
    }

    public func respond(_ command: String, _ arguments: [String], stdout: String, status: Int32 = 0) {
        responses[Self.key(command, arguments)] = ShellResult(status: status, stdout: stdout, stderr: "")
    }

    public func locate(_ command: String) -> String? {
        executables.contains(command) ? "/usr/bin/\(command)" : nil
    }

    public func run(_ command: String, _ arguments: [String], cwd: String?) throws -> ShellResult {
        let key = Self.key(command, arguments)
        calls.append(key)
        guard let result = responses[key] else { throw Error.unexpected(key) }
        return result
    }
}
