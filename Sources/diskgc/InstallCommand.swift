import ArgumentParser
import Foundation
import DiskGCCore

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install", abstract: "Install the binary to ~/.local/bin and load the launchd agent.")

    func run() throws {
        let env = try Environment()
        let fs = FileManager.default
        if !fs.fileExists(atPath: env.configPath) {
            try fs.createDirectory(atPath: (env.configPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try Config.default.defaultYAML.write(toFile: env.configPath, atomically: true, encoding: .utf8)
            print("wrote default config to \(env.configPath)")
        }
        guard let source = Bundle.main.executableURL?.path else { throw ValidationError("cannot locate the running binary") }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        let plist = try LaunchAgent.install(binarySource: RealPath.resolve(source), home: env.home, logDir: env.logDir, path: path, shell: env.shell, fs: fs)
        print("installed \(LaunchAgent.binaryPath(home: env.home)) and loaded \(plist) (every \(LaunchAgent.intervalSeconds / 60) min)")
    }
}

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Unload and remove the launchd agent.")

    func run() throws {
        let env = try Environment()
        try LaunchAgent.uninstall(home: env.home, shell: env.shell, fs: .default)
        print("removed \(LaunchAgent.plistPath(home: env.home))")
    }
}
