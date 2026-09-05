import Foundation
import Testing
@testable import DiskGCCore

@Suite struct StatusReportTests {
    @Test func byteFormatting() {
        #expect(ByteFormat.string(0) == "0 B")
        #expect(ByteFormat.string(1536) == "1.5 KB")
        #expect(ByteFormat.string(12 * ByteFormat.gigabyte + ByteFormat.gigabyte / 3) == "12.3 GB")
        #expect(ByteFormat.gigabytes(ByteFormat.gigabyte * 3 / 2) == "1.5")
    }

    @Test func groupsAreSummarisedAutoFirstThenBySize() throws {
        let gb = ByteFormat.gigabyte
        let candidates = [
            Candidate(scanner: .dockerImages, tier: .ask, group: "Docker images", id: "i", label: "i", sizeBytes: 16 * gb, staleDays: 3, actions: []),
            Candidate(scanner: .toolCaches, tier: .auto, group: "Tool caches", id: "uv", label: "uv", sizeBytes: 11 * gb, staleDays: 2, actions: []),
            Candidate(scanner: .buildArtifacts, tier: .auto, group: "Build artifacts", id: "a", label: "a", sizeBytes: 5 * gb, staleDays: 40, actions: []),
            Candidate(scanner: .buildArtifacts, tier: .auto, group: "Build artifacts", id: "b", label: "b", sizeBytes: 7 * gb, staleDays: 9, actions: []),
        ]
        let report = StatusReport(generatedAt: Date(), freeBytes: 23 * gb, targetBytes: 60 * gb, candidates: candidates, errors: ["x: boom"])
        #expect(report.groups == [
            GroupSummary(tier: .auto, group: "Build artifacts", count: 2, sizeBytes: 12 * gb, maxStaleDays: 40),
            GroupSummary(tier: .auto, group: "Tool caches", count: 1, sizeBytes: 11 * gb, maxStaleDays: 2),
            GroupSummary(tier: .ask, group: "Docker images", count: 1, sizeBytes: 16 * gb, maxStaleDays: 3),
        ])
        #expect(report.total(.auto) == 23 * gb)
        let text = report.render(verbose: true)
        #expect(text.hasPrefix("Free: 23.0 GB (target 60.0 GB)"))
        #expect(text.contains("Build artifacts"))
        #expect(text.contains("      b "))
        #expect(text.contains("warning: x: boom"))
        #expect(try report.json().contains("\"freeBytes\""))
    }
}
