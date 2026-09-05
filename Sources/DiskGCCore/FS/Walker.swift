import Foundation

public enum Walker {
    public static func directories(named names: Set<String>, under root: String, maxDepth: Int, skipping: Set<String>, fs: FileManager) -> [String] {
        var found: [String] = []
        walk(root, depth: 0, names: names, maxDepth: maxDepth, skipping: skipping, fs: fs, into: &found)
        return found
    }

    private static func walk(_ dir: String, depth: Int, names: Set<String>, maxDepth: Int, skipping: Set<String>, fs: FileManager, into found: inout [String]) {
        guard depth < maxDepth, let entries = try? fs.contentsOfDirectory(atPath: dir) else { return }
        for entry in entries.sorted() {
            let path = "\(dir)/\(entry)"
            guard isRealDirectory(path, fs: fs) else { continue }
            if names.contains(entry) {
                found.append(path)
                continue
            }
            if skipping.contains(entry) { continue }
            walk(path, depth: depth + 1, names: names, maxDepth: maxDepth, skipping: skipping, fs: fs, into: &found)
        }
    }

    public static func isRealDirectory(_ path: String, fs: FileManager) -> Bool {
        guard let attributes = try? fs.attributesOfItem(atPath: path),
              let type = attributes[.type] as? FileAttributeType else { return false }
        return type == .typeDirectory
    }

    public static func subdirectories(of dir: String, fs: FileManager) -> [String] {
        ((try? fs.contentsOfDirectory(atPath: dir)) ?? [])
            .sorted()
            .map { "\(dir)/\($0)" }
            .filter { isRealDirectory($0, fs: fs) }
    }

    public static func modificationDate(_ path: String, fs: FileManager) -> Date? {
        (try? fs.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    public static func newestEntryDate(in dir: String, fs: FileManager) -> Date? {
        var newest = modificationDate(dir, fs: fs)
        for entry in (try? fs.contentsOfDirectory(atPath: dir)) ?? [] {
            if let date = modificationDate("\(dir)/\(entry)", fs: fs), newest.map({ date > $0 }) ?? true {
                newest = date
            }
        }
        return newest
    }
}
