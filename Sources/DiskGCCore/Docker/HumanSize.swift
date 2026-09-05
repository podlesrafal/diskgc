import Foundation

public enum HumanSize {
    static let units: [String: Double] = [
        "B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12,
        "KIB": 1024, "MIB": 1024 * 1024, "GIB": 1024 * 1024 * 1024, "TIB": 1024 * 1024 * 1024 * 1024,
    ]

    public static func bytes(_ text: String) -> Int64 {
        let head = text.split(separator: "(").first.map(String.init) ?? text
        let compact = head.replacingOccurrences(of: " ", with: "")
        let digits = compact.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(digits) else { return 0 }
        let unit = compact.dropFirst(digits.count).uppercased()
        return Int64((value * (units[unit] ?? 1)).rounded())
    }
}
