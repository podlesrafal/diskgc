import Foundation

public struct CandidateGroup: Equatable, Sendable {
    public let name: String
    public let candidates: [Candidate]

    public var sizeBytes: Int64 { candidates.reduce(0) { $0 + $1.sizeBytes } }
}

public enum GroupState: Sendable {
    case none, some, all
}

public struct CandidateSelection {
    public private(set) var groups: [CandidateGroup]
    public private(set) var selected: Set<String> = []

    public init(candidates: [Candidate] = []) {
        groups = Self.group(candidates)
    }

    public var selectedCandidates: [Candidate] {
        groups.flatMap(\.candidates).filter { selected.contains($0.id) }
    }

    public var selectedCount: Int { selectedCandidates.count }

    public var selectedBytes: Int64 { selectedCandidates.reduce(0) { $0 + $1.sizeBytes } }

    public mutating func update(candidates: [Candidate]) {
        groups = Self.group(candidates)
        selected.formIntersection(candidates.map(\.id))
    }

    public func state(ofGroup name: String) -> GroupState {
        guard let group = groups.first(where: { $0.name == name }) else { return .none }
        let picked = group.candidates.count { selected.contains($0.id) }
        if picked == 0 { return .none }
        return picked == group.candidates.count ? .all : .some
    }

    public mutating func toggle(id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    public mutating func toggle(group name: String) {
        guard let group = groups.first(where: { $0.name == name }) else { return }
        let ids = group.candidates.map(\.id)
        if state(ofGroup: name) == .all { selected.subtract(ids) } else { selected.formUnion(ids) }
    }

    static func group(_ candidates: [Candidate]) -> [CandidateGroup] {
        Dictionary(grouping: candidates, by: \.group)
            .map { CandidateGroup(name: $0.key, candidates: $0.value.sorted { ($0.sizeBytes, $1.id) > ($1.sizeBytes, $0.id) }) }
            .sorted { ($0.sizeBytes, $1.name) > ($1.sizeBytes, $0.name) }
    }
}
