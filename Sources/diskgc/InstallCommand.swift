import ArgumentParser
import Foundation
import DiskGCCore

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install", abstract: "Install the app and CLI, and load the launchd agent.")

    @Option(name: .long, help: "Path to DiskGC.app; defaults to the bundle next to the running binary.")
    var app: String?

    func run() throws {
        let env = try Runtime()
        let fs = FileManager.default
        if !fs.fileExists(atPath: env.configPath) {
            try fs.createDirectory(atPath: (env.configPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try Config.default.defaultYAML.write(toFile: env.configPath, atomically: true, encoding: .utf8)
            print("wrote default config to \(env.configPath)")
        }
        guard let source = Bundle.main.executableURL?.path else { throw ValidationError("cannot locate the running binary") }
        let binary = RealPath.resolve(source)
        guard let bundle = app ?? LaunchAgent.bundledApp(near: binary, fs: fs) else {
            throw ValidationError("cannot find \(LaunchAgent.appName); run Scripts/bundle.sh first or pass --app")
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        let plist = try LaunchAgent.install(
            binarySource: binary, appSource: bundle, home: env.home,
            logDir: env.logDir, path: path, shell: env.shell, fs: fs
        )
        print("installed \(LaunchAgent.appPath(home: env.home)) and \(LaunchAgent.binaryPath(home: env.home))")
        print("loaded \(plist)")
    }
}

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Unload the agent and remove the installed app.")

    func run() throws {
        let env = try Runtime()
        try LaunchAgent.uninstall(home: env.home, shell: env.shell, fs: .default)
        print("removed \(LaunchAgent.plistPath(home: env.home)) and \(LaunchAgent.appPath(home: env.home))")
    }
}
