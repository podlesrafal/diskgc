import Foundation

public enum DiskSpace {
    public static func freeBytes(at path: String) throws -> Int64 {
        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard let capacity = values.volumeAvailableCapacity else { throw DiskSpaceError.unavailable(path) }
        return Int64(capacity)
    }
}

public enum DiskSpaceError: Error, Equatable {
    case unavailable(String)
}
