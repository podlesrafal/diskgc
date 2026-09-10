import Foundation
import Yams

public struct InactiveDays: Codable, Equatable, Sendable {
    public var buildArtifacts: Int
    public var worktree: Int
    public var dockerContainer: Int
    public var derivedData: Int
    public var jetbrains: Int
    public var claudeScratch: Int

    public init(buildArtifacts: Int = 7, worktree: Int = 21, dockerContainer: Int = 3, derivedData: Int = 14, jetbrains: Int = 30, claudeScratch: Int = 14) {
        self.buildArtifacts = buildArtifacts
        self.worktree = worktree
        self.dockerContainer = dockerContainer
        self.derivedData = derivedData
        self.jetbrains = jetbrains
        self.claudeScratch = claudeScratch
    }

    enum CodingKeys: String, CodingKey {
        case buildArtifacts = "build_artifacts"
        case worktree
        case dockerContainer = "docker_container"
        case derivedData = "derived_data"
        case jetbrains
        case claudeScratch = "claude_scratch"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = InactiveDays()
        buildArtifacts = try c.decodeIfPresent(Int.self, forKey: .buildArtifacts) ?? d.buildArtifacts
        worktree = try c.decodeIfPresent(Int.self, forKey: .worktree) ?? d.worktree
        dockerContainer = try c.decodeIfPresent(Int.self, forKey: .dockerContainer) ?? d.dockerContainer
        derivedData = try c.decodeIfPresent(Int.self, forKey: .derivedData) ?? d.derivedData
        jetbrains = try c.decodeIfPresent(Int.self, forKey: .jetbrains) ?? d.jetbrains
        claudeScratch = try c.decodeIfPresent(Int.self, forKey: .claudeScratch) ?? d.claudeScratch
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var targetFreeGB: Int
    public var warnFreeGB: Int
    public var warnCooldownHours: Int
    public var notifyMinGB: Int
    public var notifyCooldownHours: Int
    public var rescanHours: Int
    public var projectRoots: [String]
    public var inactiveDays: InactiveDays
    public var scanners: [ScannerID: Tier]
    public var never: [String]

    public static let `default` = Config()

    public static let defaultTiers: [ScannerID: Tier] = [
        .toolCaches: .auto, .buildArtifacts: .auto, .xcode: .auto, .jetbrains: .auto,
        .updaterCaches: .auto, .claudeScratch: .auto,
        .dockerContainers: .ask, .dockerImages: .ask, .dockerBuildCache: .ask, .dockerVolumes: .ask,
        .worktrees: .ask,
    ]

    public init(
        targetFreeGB: Int = 60, warnFreeGB: Int = 15, warnCooldownHours: Int = 3,
        notifyMinGB: Int = 5, notifyCooldownHours: Int = 24, rescanHours: Int = 6,
        projectRoots: [String] = ["~/Documents/Projects"], inactiveDays: InactiveDays = InactiveDays(),
        scanners: [ScannerID: Tier] = Config.defaultTiers,
        never: [String] = ["~/.m2", "~/Library/Application Support/Claude"]
    ) {
        self.targetFreeGB = targetFreeGB
        self.warnFreeGB = warnFreeGB
        self.warnCooldownHours = warnCooldownHours
        self.notifyMinGB = notifyMinGB
        self.notifyCooldownHours = notifyCooldownHours
        self.rescanHours = rescanHours
        self.projectRoots = projectRoots
        self.inactiveDays = inactiveDays
        self.scanners = scanners
        self.never = never
    }

    enum CodingKeys: String, CodingKey {
        case targetFreeGB = "target_free_gb"
        case warnFreeGB = "warn_free_gb"
        case warnCooldownHours = "warn_cooldown_hours"
        case notifyMinGB = "notify_min_gb"
        case notifyCooldownHours = "notify_cooldown_hours"
        case rescanHours = "rescan_hours"
        case projectRoots = "project_roots"
        case inactiveDays = "inactive_days"
        case scanners
        case never
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        targetFreeGB = try c.decodeIfPresent(Int.self, forKey: .targetFreeGB) ?? d.targetFreeGB
        warnFreeGB = try c.decodeIfPresent(Int.self, forKey: .warnFreeGB) ?? d.warnFreeGB
        warnCooldownHours = try c.decodeIfPresent(Int.self, forKey: .warnCooldownHours) ?? d.warnCooldownHours
        notifyMinGB = try c.decodeIfPresent(Int.self, forKey: .notifyMinGB) ?? d.notifyMinGB
        notifyCooldownHours = try c.decodeIfPresent(Int.self, forKey: .notifyCooldownHours) ?? d.notifyCooldownHours
        rescanHours = try c.decodeIfPresent(Int.self, forKey: .rescanHours) ?? d.rescanHours
        projectRoots = try c.decodeIfPresent([String].self, forKey: .projectRoots) ?? d.projectRoots
        inactiveDays = try c.decodeIfPresent(InactiveDays.self, forKey: .inactiveDays) ?? d.inactiveDays
        let overrides = try c.decodeIfPresent([String: Tier].self, forKey: .scanners) ?? [:]
        var tiers = Config.defaultTiers
        for (key, tier) in overrides {
            guard let id = ScannerID(rawValue: key) else { throw ConfigError.unknownScanner(key) }
            tiers[id] = tier
        }
        scanners = tiers
        never = try c.decodeIfPresent([String].self, forKey: .never) ?? d.never
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(targetFreeGB, forKey: .targetFreeGB)
        try c.encode(warnFreeGB, forKey: .warnFreeGB)
        try c.encode(warnCooldownHours, forKey: .warnCooldownHours)
        try c.encode(notifyMinGB, forKey: .notifyMinGB)
        try c.encode(notifyCooldownHours, forKey: .notifyCooldownHours)
        try c.encode(rescanHours, forKey: .rescanHours)
        try c.encode(projectRoots, forKey: .projectRoots)
        try c.encode(inactiveDays, forKey: .inactiveDays)
        try c.encode(Dictionary(uniqueKeysWithValues: scanners.map { ($0.key.rawValue, $0.value) }), forKey: .scanners)
        try c.encode(never, forKey: .never)
    }

    public static func parse(yaml: String) throws -> Config {
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .default }
        return try YAMLDecoder().decode(Config.self, from: yaml)
    }

    public static func load(from path: String, home: String) throws -> Config {
        guard FileManager.default.fileExists(atPath: path) else { return Config.default.expanded(home: home) }
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return try parse(yaml: text).expanded(home: home)
    }

    public func expanded(home: String) -> Config {
        var copy = self
        copy.projectRoots = projectRoots.map { Self.expand($0, home: home) }
        copy.never = never.map { Self.expand($0, home: home) }
        return copy
    }

    public static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    public func tier(of id: ScannerID) -> Tier {
        scanners[id] ?? Config.defaultTiers[id] ?? .off
    }

    public var defaultYAML: String {
        let tiers = ScannerID.allCases.map { "  \($0.rawValue): \(tier(of: $0).rawValue)" }.joined(separator: "\n")
        let roots = projectRoots.map { "  - \($0)" }.joined(separator: "\n")
        let nevers = never.map { "  - \"\($0)\"" }.joined(separator: "\n")
        return """
        target_free_gb: \(targetFreeGB)
        warn_free_gb: \(warnFreeGB)
        warn_cooldown_hours: \(warnCooldownHours)
        notify_min_gb: \(notifyMinGB)
        notify_cooldown_hours: \(notifyCooldownHours)
        rescan_hours: \(rescanHours)
        project_roots:
        \(roots)
        inactive_days:
          build_artifacts: \(inactiveDays.buildArtifacts)
          worktree: \(inactiveDays.worktree)
          docker_container: \(inactiveDays.dockerContainer)
          derived_data: \(inactiveDays.derivedData)
          jetbrains: \(inactiveDays.jetbrains)
          claude_scratch: \(inactiveDays.claudeScratch)
        scanners:
        \(tiers)
        never:
        \(nevers)

        """
    }
}

public enum ConfigError: Error, Equatable {
    case unknownScanner(String)
}
