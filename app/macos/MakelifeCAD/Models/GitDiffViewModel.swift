import Foundation

// MARK: - Component diff entry

struct ComponentDiff: Identifiable {
    enum Change {
        case added
        case removed
        case valueChanged(old: String, new: String)
        case footprintChanged(old: String, new: String)
    }

    let id = UUID()
    let reference: String
    let value: String
    let footprint: String
    let change: Change

    var icon: String {
        switch change {
        case .added:             return "plus.circle.fill"
        case .removed:           return "minus.circle.fill"
        case .valueChanged:      return "pencil.circle.fill"
        case .footprintChanged:  return "rectangle.and.pencil.and.ellipsis"
        }
    }

    var changeLabel: String {
        switch change {
        case .added:               return "Added"
        case .removed:             return "Removed"
        case .valueChanged(let o, let n):     return "\(o) → \(n)"
        case .footprintChanged(let o, let n): return "\(o) → \(n)"
        }
    }
}

// MARK: - GitDiffViewModel

@MainActor
final class GitDiffViewModel: ObservableObject {

    enum State {
        case idle
        case loading
        case done([ComponentDiff])
        case error(String)
        case noGit
        case noHistory
        case clean
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var schematicPath: String = ""
    @Published private(set) var commitSHA: String = ""

    // MARK: - Public

    /// Diff current loaded components against HEAD version of the same file.
    func diff(currentComponents: [SchematicComponent], fileURL: URL) async {
        schematicPath = fileURL.lastPathComponent
        state = .loading

        // 1. Find git repo root (walk up from file location)
        guard let gitRoot = findGitRoot(from: fileURL.deletingLastPathComponent()) else {
            state = .noGit
            return
        }

        // 2. Get relative path from git root
        let relativePath = fileURL.path
            .replacingOccurrences(of: gitRoot.path + "/", with: "")

        // 3. Get HEAD SHA for context
        commitSHA = (try? shellOutput("git", ["-C", gitRoot.path, "rev-parse", "--short", "HEAD"])) ?? "HEAD"

        // 4. Check if file is tracked and has history
        let tracked = try? shellOutput("git", ["-C", gitRoot.path, "log", "--oneline", "-1", "--", relativePath])
        guard let tracked, !tracked.isEmpty else {
            state = .noHistory
            return
        }

        // 5. Get HEAD version of the file
        guard let headContent = try? shellOutput("git", ["-C", gitRoot.path, "show", "HEAD:\(relativePath)"]),
              !headContent.isEmpty else {
            state = .noHistory
            return
        }

        // 6. Parse old components from HEAD content via temp file + bridge
        let headComponents = await parseComponents(from: headContent)

        // 7. Compute diff
        let diffs = computeDiff(head: headComponents, current: currentComponents)
        if diffs.isEmpty {
            state = .clean
        } else {
            state = .done(diffs)
        }
    }

    // MARK: - Private

    /// Walk up directory tree to find .git folder
    private func findGitRoot(from dir: URL) -> URL? {
        var current = dir
        for _ in 0..<20 {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }
        return nil
    }

    /// Run a command and return trimmed stdout
    private func shellOutput(_ executable: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/\(executable)")
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Write content to a temp file, open with KiCadBridge, return components
    private func parseComponents(from content: String) async -> [SchematicComponent] {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("makelife_diff_\(UUID().uuidString).kicad_sch")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        guard (try? content.write(to: tmpURL, atomically: true, encoding: .utf8)) != nil else {
            return []
        }

        let bridge = KiCadBridge()
        guard (try? bridge.openSchematic(path: tmpURL.path)) != nil else { return [] }
        let components = bridge.components
        bridge.close()
        return components
    }

    /// Returns the diff between HEAD and current component lists
    private func computeDiff(head: [SchematicComponent], current: [SchematicComponent]) -> [ComponentDiff] {
        var diffs: [ComponentDiff] = []

        let headByRef   = Dictionary(uniqueKeysWithValues: head.map    { ($0.reference, $0) })
        let currentByRef = Dictionary(uniqueKeysWithValues: current.map { ($0.reference, $0) })

        // Removed
        for (ref, comp) in headByRef where currentByRef[ref] == nil {
            diffs.append(ComponentDiff(reference: ref, value: comp.value,
                                       footprint: comp.footprint, change: .removed))
        }

        // Added or Modified
        for (ref, comp) in currentByRef {
            if let old = headByRef[ref] {
                if old.value != comp.value {
                    diffs.append(ComponentDiff(reference: ref, value: comp.value,
                                               footprint: comp.footprint,
                                               change: .valueChanged(old: old.value, new: comp.value)))
                } else if old.footprint != comp.footprint {
                    diffs.append(ComponentDiff(reference: ref, value: comp.value,
                                               footprint: comp.footprint,
                                               change: .footprintChanged(old: old.footprint, new: comp.footprint)))
                }
            } else {
                diffs.append(ComponentDiff(reference: ref, value: comp.value,
                                           footprint: comp.footprint, change: .added))
            }
        }

        return diffs.sorted { $0.reference < $1.reference }
    }
}
