import Foundation

public enum PressurePlanner {
    public static func order(_ candidates: [Candidate]) -> [Candidate] {
        candidates.sorted { a, b in
            if a.staleDays != b.staleDays { return a.staleDays > b.staleDays }
            if a.sizeBytes != b.sizeBytes { return a.sizeBytes > b.sizeBytes }
            return a.id < b.id
        }
    }
}
