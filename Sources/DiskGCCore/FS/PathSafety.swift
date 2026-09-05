import Foundation

public enum PathSafetyError: Error, Equatable {
    case notAbsolute
    case symlink
    case notDirectory
    case tooShallow
    case outsideRoot
    case equalsRoot
    case underNever
}

public enum PathSafety {
    public static let minimumComponents = 4

    public static func validate(_ rawPath: String, root rawRoot: String, never: [String], fs: FileManager) throws {
        guard rawPath.hasPrefix("/") else { throw PathSafetyError.notAbsolute }
        let path = normalize(rawPath)
        let root = normalize(rawRoot)
        if let type = try? fs.attributesOfItem(atPath: path)[.type] as? FileAttributeType, type == .typeSymbolicLink {
            throw PathSafetyError.symlink
        }
        var isDirectory: ObjCBool = false
        guard fs.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PathSafetyError.notDirectory
        }
        guard path.split(separator: "/").count >= minimumComponents else { throw PathSafetyError.tooShallow }
        guard path != root else { throw PathSafetyError.equalsRoot }
        guard isInside(path, root) else { throw PathSafetyError.outsideRoot }
        for forbidden in never.map(normalize) where path == forbidden || isInside(path, forbidden) {
            throw PathSafetyError.underNever
        }
    }

    public static func normalize(_ path: String) -> String {
        var components: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..": _ = components.popLast()
            default: components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }

    public static func isInside(_ path: String, _ directory: String) -> Bool {
        path.hasPrefix(directory.hasSuffix("/") ? directory : directory + "/")
    }
}
