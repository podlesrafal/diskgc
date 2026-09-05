import Foundation
@testable import DiskGCCore

enum TestSupport {
    static func tempDir(_ name: String = "diskgc") -> String {
        let path = NSTemporaryDirectory() + "\(name)-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return RealPath.resolve(path)
    }

    static func mkdir(_ path: String) {
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    static func touch(_ path: String, content: String = "") {
        mkdir((path as NSString).deletingLastPathComponent)
        try! content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func setModificationDate(_ path: String, daysAgo: Int) {
        let date = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        try! FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
    }
}
