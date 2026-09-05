import Foundation

public enum LaunchAgent {
    public static let label = "dev.rpo.diskgc"
    public static let intervalSeconds = 1800

    public static func plistPath(home: String) -> String {
        "\(home)/Library/LaunchAgents/\(label).plist"
    }

    public static func binaryPath(home: String) -> String {
        "\(home)/.local/bin/diskgc"
    }

    public static func plist(binary: String, logDir: String, path: String, intervalSeconds: Int) -> String {
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
                <string>tick</string>
            </array>
            <key>StartInterval</key>
            <integer>\(intervalSeconds)</integer>
            <key>RunAtLoad</key>
            <true/>
            <key>ProcessType</key>
            <string>Background</string>
            <key>Nice</key>
            <integer>10</integer>
            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>\(escape(path))</string>
            </dict>
            <key>StandardOutPath</key>
            <string>\(escape(logDir))/tick.log</string>
            <key>StandardErrorPath</key>
            <string>\(escape(logDir))/tick.err.log</string>
        </dict>
        </plist>

        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    @discardableResult
    public static func install(binarySource: String, home: String, logDir: String, path: String, shell: ShellRunner, fs: FileManager) throws -> String {
        let binary = binaryPath(home: home)
        try fs.createDirectory(atPath: (binary as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try fs.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        try fs.createDirectory(atPath: "\(home)/Library/LaunchAgents", withIntermediateDirectories: true)
        if fs.fileExists(atPath: binary) { try fs.removeItem(atPath: binary) }
        try fs.copyItem(atPath: binarySource, toPath: binary)
        let plistFile = plistPath(home: home)
        try plist(binary: binary, logDir: logDir, path: path, intervalSeconds: intervalSeconds).write(toFile: plistFile, atomically: true, encoding: .utf8)
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
    }
}

public enum LaunchAgentError: Error, Equatable {
    case launchctlFailed(String)
}
