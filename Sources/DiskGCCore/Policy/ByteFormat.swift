import Foundation

public enum ByteFormat {
    public static let gigabyte: Int64 = 1024 * 1024 * 1024

    public static func string(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        let text = index == 0 ? String(Int(value)) : String(format: "%.1f", value)
        return "\(text) \(units[index])"
    }

    public static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / Double(gigabyte))
    }
}
