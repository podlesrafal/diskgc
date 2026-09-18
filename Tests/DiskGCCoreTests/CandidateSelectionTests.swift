import Foundation
import Testing
@testable import DiskGCCore

@Suite struct CandidateSelectionTests {
    static let gb = ByteFormat.gigabyte

    static func image(_ id: String, _ sizeBytes: Int64) -> Candidate {
        Candidate(scanner: .dockerImages, tier: .ask, group: "Docker images", id: id, label: id, sizeBytes: sizeBytes, staleDays: 3, actions: [])
    }

    static func artifact(_ id: String, _ sizeBytes: Int64) -> Candidate {
        Candidate(scanner: .buildArtifacts, tier: .ask, group: "Build artifacts", id: id, label: id, sizeBytes: sizeBytes, staleDays: 30, actions: [])
    }

    @Test func groupsCandidatesBySectionLargestFirst() {
        let gb = Self.gb
        let selection = CandidateSelection(candidates: [Self.image("a", gb), Self.artifact("x", 5 * gb), Self.image("b", 2 * gb)])
        #expect(selection.groups.map(\.name) == ["Build artifacts", "Docker images"])
        #expect(selection.groups.last?.candidates.map(\.id) == ["b", "a"])
        #expect(selection.groups.last?.sizeBytes == 3 * gb)
    }

    @Test func nothingIsSelectedUntilARowIsToggled() {
        let gb = Self.gb
        var selection = CandidateSelection(candidates: [Self.image("a", gb), Self.image("b", 2 * gb)])
        #expect(selection.selectedCount == 0)
        #expect(selection.selectedBytes == 0)
        selection.toggle(id: "b")
        #expect(selection.selectedCount == 1)
        #expect(selection.selectedBytes == 2 * gb)
        #expect(selection.selectedCandidates.map(\.id) == ["b"])
        selection.toggle(id: "b")
        #expect(selection.selectedCount == 0)
    }

    @Test func groupReportsWhetherNoneSomeOrAllOfItIsSelected() {
        let gb = Self.gb
        var selection = CandidateSelection(candidates: [Self.image("a", gb), Self.image("b", 2 * gb)])
        #expect(selection.state(ofGroup: "Docker images") == .none)
        selection.toggle(id: "a")
        #expect(selection.state(ofGroup: "Docker images") == .some)
        selection.toggle(id: "b")
        #expect(selection.state(ofGroup: "Docker images") == .all)
    }

    @Test func togglingAPartlySelectedGroupSelectsTheRestRatherThanClearingIt() {
        let gb = Self.gb
        var selection = CandidateSelection(candidates: [Self.image("a", gb), Self.image("b", 2 * gb), Self.artifact("x", gb)])
        selection.toggle(id: "a")
        selection.toggle(group: "Docker images")
        #expect(selection.state(ofGroup: "Docker images") == .all)
        #expect(selection.selectedBytes == 3 * gb)
        selection.toggle(group: "Docker images")
        #expect(selection.state(ofGroup: "Docker images") == .none)
        #expect(selection.selectedCount == 0)
    }

    @Test func refreshKeepsRowsThatSurvivedAndForgetsTheOnesThatVanished() {
        let gb = Self.gb
        var selection = CandidateSelection(candidates: [Self.image("a", gb), Self.image("b", 2 * gb)])
        selection.toggle(group: "Docker images")
        selection.update(candidates: [Self.image("a", 4 * gb), Self.image("c", 3 * gb)])
        #expect(selection.selectedCandidates.map(\.id) == ["a"])
        #expect(selection.selectedBytes == 4 * gb)
        #expect(selection.state(ofGroup: "Docker images") == .some)
    }
}
