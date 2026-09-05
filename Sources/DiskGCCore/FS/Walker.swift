import Foundation

public struct DirectoryEntry: Equatable {
    public var name: String
    public var isDirectory: Bool
    public var isSymlink: Bool
}

public enum Walker {
    public static func entries(of dir: String) -> [DirectoryEntry] {
        guard let handle = opendir(dir) else { return [] }
        defer { closedir(handle) }
        var result: [DirectoryEntry] = []
        while let entry = readdir(handle) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            guard name != ".", name != ".." else { continue }
            var type = Int32(entry.pointee.d_type)
            if type == DT_UNKNOWN {
                var info = stat()
                type = lstat("\(dir)/\(name)", &info) == 0 ? ((info.st_mode & S_IFMT) == S_IFDIR ? DT_DIR : ((info.st_mode & S_IFMT) == S_IFLNK ? DT_LNK : DT_REG)) : DT_REG
            }
            result.append(DirectoryEntry(name: name, isDirectory: type == DT_DIR, isSymlink: type == DT_LNK))
        }
        return result.sorted { $0.name < $1.name }
    }

    public static func directories(named names: Set<String>, under root: String, maxDepth: Int, skipping: Set<String>, fs: FileManager) -> [String] {
        var found: [String] = []
        walk(root, depth: 0, names: names, maxDepth: maxDepth, skipping: skipping, into: &found)
        return found
    }

    private static func walk(_ dir: String, depth: Int, names: Set<String>, maxDepth: Int, skipping: Set<String>, into found: inout [String]) {
        guard depth < maxDepth else { return }
        for entry in entries(of: dir) where entry.isDirectory {
            let path = "\(dir)/\(entry.name)"
            if names.contains(entry.name) {
                found.append(path)
                continue
            }
            if skipping.contains(entry.name) { continue }
            walk(path, depth: depth + 1, names: names, maxDepth: maxDepth, skipping: skipping, into: &found)
        }
    }

    public static func isRealDirectory(_ path: String, fs: FileManager) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    public static func subdirectories(of dir: String, fs: FileManager) -> [String] {
        entries(of: dir).filter(\.isDirectory).map { "\(dir)/\($0.name)" }
    }

    public static func modificationDate(_ path: String, fs: FileManager) -> Date? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
    }

    public static func newestEntryDate(in dir: String, fs: FileManager) -> Date? {
        var newest = modificationDate(dir, fs: fs)
        for entry in entries(of: dir) {
            if let date = modificationDate("\(dir)/\(entry.name)", fs: fs), newest.map({ date > $0 }) ?? true {
                newest = date
            }
        }
        return newest
    }

    public static func workTree(containing path: String) -> String? {
        var current = path
        while current != "/" && !current.isEmpty {
            var info = stat()
            if lstat("\(current)/.git", &info) == 0 { return current }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }
}
