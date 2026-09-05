import Foundation

public struct GroupSummary: Codable, Equatable {
    public var tier: Tier
    public var group: String
    public var count: Int
    public var sizeBytes: Int64
    public var maxStaleDays: Int
}

public struct StatusReport: Codable, Equatable {
    public var generatedAt: Date
    public var freeBytes: Int64
    public var targetBytes: Int64
    public var groups: [GroupSummary]
    public var candidates: [Candidate]
    public var errors: [String]

    public init(generatedAt: Date, freeBytes: Int64, targetBytes: Int64, candidates: [Candidate], errors: [String]) {
        self.generatedAt = generatedAt
        self.freeBytes = freeBytes
        self.targetBytes = targetBytes
        self.candidates = candidates
        self.errors = errors
        self.groups = Self.summarize(candidates)
    }

    public static func summarize(_ candidates: [Candidate]) -> [GroupSummary] {
        var byKey: [String: GroupSummary] = [:]
        for candidate in candidates {
            let key = "\(candidate.tier.rawValue)|\(candidate.group)"
            var summary = byKey[key] ?? GroupSummary(tier: candidate.tier, group: candidate.group, count: 0, sizeBytes: 0, maxStaleDays: 0)
            summary.count += 1
            summary.sizeBytes += candidate.sizeBytes
            summary.maxStaleDays = max(summary.maxStaleDays, candidate.staleDays)
            byKey[key] = summary
        }
        return byKey.values.sorted { a, b in
            if a.tier != b.tier { return a.tier == .auto }
            return a.sizeBytes > b.sizeBytes
        }
    }

    public func total(_ tier: Tier) -> Int64 {
        groups.filter { $0.tier == tier }.reduce(0) { $0 + $1.sizeBytes }
    }

    public func render(verbose: Bool = false) -> String {
        var lines: [String] = []
        lines.append("Free: \(ByteFormat.string(freeBytes)) (target \(ByteFormat.string(targetBytes)))")
        for tier in [Tier.auto, .ask] {
            let tierGroups = groups.filter { $0.tier == tier }
            guard !tierGroups.isEmpty else { continue }
            let heading = tier == .auto ? "AUTO (removed under pressure)" : "ASK (diskgc review)"
            lines.append("")
            lines.append(Self.row(heading, "items", "size", "oldest"))
            for group in tierGroups {
                lines.append(Self.row("  " + group.group, String(group.count), ByteFormat.string(group.sizeBytes), "\(group.maxStaleDays)d"))
                guard verbose else { continue }
                for candidate in candidates.filter({ $0.tier == tier && $0.group == group.group }).sorted(by: { $0.sizeBytes > $1.sizeBytes }) {
                    let detail = candidate.detail.map { "  (\($0))" } ?? ""
                    lines.append("      " + Self.pad(candidate.label, 62) + Self.lpad(ByteFormat.string(candidate.sizeBytes), 11) + Self.lpad("\(candidate.staleDays)d", 7) + detail)
                }
            }
            lines.append(Self.row("  total", "", ByteFormat.string(total(tier)), ""))
        }
        if groups.isEmpty { lines.append("Nothing to reclaim.") }
        for error in errors { lines.append("warning: \(error)") }
        return lines.joined(separator: "\n")
    }

    static func row(_ a: String, _ b: String, _ c: String, _ d: String) -> String {
        pad(a, 42) + lpad(b, 6) + lpad(c, 11) + lpad(d, 8)
    }

    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    static func lpad(_ text: String, _ width: Int) -> String {
        text.count >= width ? " " + text : String(repeating: " ", count: width - text.count) + text
    }

    public func json() throws -> String {
        String(decoding: try JSONCoding.encoder.encode(self), as: UTF8.self)
    }
}
