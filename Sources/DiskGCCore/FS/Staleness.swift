import Foundation

public enum Staleness {
    public static func days(since date: Date?, now: Date) -> Int {
        guard let date else { return 0 }
        return max(0, Int(now.timeIntervalSince(date) / 86_400))
    }
}
