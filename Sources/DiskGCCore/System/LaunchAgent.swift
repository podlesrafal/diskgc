import Foundation

public enum LaunchAgent {
    public static let label = "dev.rpo.diskgc"
    public static let appName = "DiskGC.app"
    public static let appBinaryName = "DiskGCBar"
    public static let throttleSeconds = 30

    public static func plistPath(home: String) -> String {
        "\(home)/Library/LaunchAgents/\(label).plist"
    }

    public static func binaryPath(home: String) -> String {
        "\(home)/.local/bin/diskgc"
    }

    public static func appPath(home: String) -> String {
        "\(home)/Applications/\(appName)"
    }

    public static func appBinaryPath(home: String) -> String {
        "\(appPath(home: home))/Contents/MacOS/\(appBinaryName)"
    }

    // SwiftPM symlinks .build/release into .build/<arch>/release, so the bundle sits a
    // varying number of levels above the resolved binary.
    public static func bundledApp(near binary: String, fs: FileManager, levels: Int = 4) -> String? {
        var directory = (binary as NSString).deletingLastPathComponent
        for _ in 0..<levels {
            let candidate = "\(directory)/\(appName)"
            if fs.fileExists(atPath: candidate) { return candidate }
            let parent = (directory as NSString).deletingLastPathComponent
            guard parent != directory, !parent.isEmpty else { break }
            directory = parent
        }
        return nil
    }

    public static func plist(binary: String, logDir: String, path: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(escape(binary))</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ThrottleInterval</key>
            <integer>\(throttleSeconds)</integer>
            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>\(escape(path))</string>
            </dict>
            <key>StandardOutPath</key>
            <string>\(escape(logDir))/bar.log</string>
            <key>StandardErrorPath</key>
            <string>\(escape(logDir))/bar.err.log</string>
        </dict>
        </plist>

        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    @discardableResult
    public static func install(binarySource: String, appSource: String, home: String, logDir: String, path: String, shell: ShellRunner, fs: FileManager) throws -> String {
        let binary = binaryPath(home: home)
        try fs.createDirectory(atPath: (binary as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try fs.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        try fs.createDirectory(atPath: "\(home)/Library/LaunchAgents", withIntermediateDirectories: true)
        try fs.createDirectory(atPath: "\(home)/Applications", withIntermediateDirectories: true)
        if fs.fileExists(atPath: binary) { try fs.removeItem(atPath: binary) }
        try fs.copyItem(atPath: binarySource, toPath: binary)
        let app = appPath(home: home)
        if fs.fileExists(atPath: app) { try fs.removeItem(atPath: app) }
        try fs.copyItem(atPath: appSource, toPath: app)
        let plistFile = plistPath(home: home)
        try plist(binary: appBinaryPath(home: home), logDir: logDir, path: path).write(toFile: plistFile, atomically: true, encoding: .utf8)
        let domain = "gui/\(getuid())"
        _ = try? shell.run("launchctl", ["bootout", domain, plistFile], cwd: nil)
        let result = try shell.run("launchctl", ["bootstrap", domain, plistFile], cwd: nil)
        guard result.succeeded else { throw LaunchAgentError.launchctlFailed(result.stderr) }
        return plistFile
    }

    public static func uninstall(home: String, shell: ShellRunner, fs: FileManager) throws {
        let plistFile = plistPath(home: home)
        _ = try? shell.run("launchctl", ["bootout", "gui/\(getuid())", plistFile], cwd: nil)
        if fs.fileExists(atPath: plistFile) { try fs.removeItem(atPath: plistFile) }
        let app = appPath(home: home)
        if fs.fileExists(atPath: app) { try fs.removeItem(atPath: app) }
    }
}

public enum LaunchAgentError: Error, Equatable {
    case launchctlFailed(String)
}
