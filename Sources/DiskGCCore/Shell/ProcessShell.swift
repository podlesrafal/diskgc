import Foundation

public struct ProcessShell: ShellRunner {
    public enum Error: Swift.Error, Equatable {
        case commandNotFound(String)
    }

    public var extraSearchPaths: [String]

    public init(extraSearchPaths: [String] = ProcessShell.defaultExtraSearchPaths) {
        self.extraSearchPaths = extraSearchPaths
    }

    public static var defaultExtraSearchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/usr/local/bin", "/opt/homebrew/bin", "\(home)/.local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    }

    public func run(_ command: String, _ arguments: [String], cwd: String?) throws -> ShellResult {
        let executable = try resolve(command)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    func resolve(_ command: String) throws -> String {
        if command.contains("/") { return command }
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let dirs = envPath.split(separator: ":").map(String.init) + extraSearchPaths
        for dir in dirs {
            let candidate = "\(dir)/\(command)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        throw Error.commandNotFound(command)
    }
}
