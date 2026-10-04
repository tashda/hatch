import Foundation

/// Finds and makes the local clone of a GitHub repository, so the owner never has to point Hatch at a folder by hand.
public enum LocalClones {
    /// Folders people usually keep code in, under the home folder. Searched a few levels deep.
    public static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        ["Development", "Developer", "Projects", "Code", "code", "src", "GitHub", "Documents/GitHub", "repos", "Sites", "Work"]
            .map { home.appendingPathComponent($0) }
    }

    /// Clones of `remote` ("owner/name") under `roots`, nearest first. A clone matches when any of its remotes points
    /// at that GitHub repository, over HTTPS or SSH, with or without `.git`.
    public static func find(_ remote: String, in roots: [URL] = defaultRoots(), depth: Int = 3) -> [String] {
        let target = remote.lowercased()
        var found: [String] = []
        var seen = Set<String>()
        for root in roots { search(root, target: target, depth: depth, found: &found, seen: &seen) }
        return found
    }

    /// Whether the git config text names `remote` as one of its remotes.
    public static func configPoints(_ config: String, at remote: String) -> Bool {
        let target = remote.lowercased()
        for line in config.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("url") , let eq = trimmed.firstIndex(of: "=") else { continue }
            if repository(fromURL: String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)) == target { return true }
        }
        return false
    }

    /// "owner/name" from a GitHub remote URL, lowercased; nil for anything else.
    public static func repository(fromURL url: String) -> String? {
        var s = url.lowercased()
        for prefix in ["https://github.com/", "http://github.com/", "ssh://git@github.com/", "git@github.com:", "git://github.com/"] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
            if s.hasSuffix("/") { s.removeLast() }
            if s.hasSuffix(".git") { s.removeLast(4) }
            let parts = s.split(separator: "/")
            return parts.count == 2 ? s : nil
        }
        return nil
    }

    /// Clones `remote` into `destination` over HTTPS. The token is passed for this one command only and is not saved
    /// in the clone's config.
    public static func clone(_ remote: String, to destination: String, token: String?, git: GitRunner = ProcessGit()) throws {
        var args: [String] = []
        if let token, !token.isEmpty {
            let basic = Data("x-access-token:\(token)".utf8).base64EncodedString()
            args += ["-c", "http.extraHeader=Authorization: Basic \(basic)"]
        }
        args += ["clone", "https://github.com/\(remote).git", destination]
        try git.git(args, in: nil)
    }

    private static func search(_ dir: URL, target: String, depth: Int, found: inout [String], seen: inout Set<String>) {
        let fm = FileManager.default
        let path = dir.resolvingSymlinksInPath().path
        guard depth >= 0, !seen.contains(path) else { return }
        seen.insert(path)
        let config = dir.appendingPathComponent(".git/config")
        if let text = try? String(contentsOf: config, encoding: .utf8) {
            if configPoints(text, at: target) { found.append(dir.path) }
            return  // a clone's own subfolders are not searched
        }
        guard depth > 0, let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if ["node_modules", "build", "DerivedData", ".build", "Pods"].contains(child.lastPathComponent) { continue }
            search(child, target: target, depth: depth - 1, found: &found, seen: &seen)
        }
    }
}

/// A build command suggested from what is at the top of a clone, for `hatch ready`. Nil when nothing is recognised.
public enum BuildCommand {
    public static func suggest(in path: String) -> String? {
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: path)) ?? []).sorted()
        if let workspace = names.first(where: { $0.hasSuffix(".xcworkspace") }) {
            let scheme = (workspace as NSString).deletingPathExtension
            return "xcodebuild -workspace \(workspace) -scheme \(scheme) build"
        }
        if let project = names.first(where: { $0.hasSuffix(".xcodeproj") }) {
            let scheme = (project as NSString).deletingPathExtension
            return "xcodebuild -project \(project) -scheme \(scheme) build"
        }
        if names.contains("Package.swift") { return "swift build" }
        return nil
    }
}
