import Foundation

// MARK: - FreeCAD document model

struct FreeCADDocumentRef: Identifiable, Equatable {
    let url: URL
    let name: String
    let relativePath: String
    let lastModified: Date?

    var id: String { url.path }
}

// MARK: - YiACAD project model

/// Represents an opened YiACAD hardware project rooted by a `.kicad_pro` file.
/// KiCad companions use KiCad naming conventions and FreeCAD files live under `mechanical/`.
struct YiacadProject: Identifiable, Equatable {
    let url: URL
    let name: String
    let rootURL: URL
    let sheets: [String]
    let designSettings: [String: Any]?
    let freecadDocuments: [FreeCADDocumentRef]

    var id: URL { url }

    var schematicURL: URL { rootURL.appendingPathComponent("\(name).kicad_sch") }
    var pcbURL: URL { rootURL.appendingPathComponent("\(name).kicad_pcb") }
    var mechanicalRootURL: URL { rootURL.appendingPathComponent("mechanical", isDirectory: true) }

    var hasSchematic: Bool { FileManager.default.fileExists(atPath: schematicURL.path) }
    var hasPCB: Bool { FileManager.default.fileExists(atPath: pcbURL.path) }
    var hasMechanicalWorkspace: Bool {
        FileManager.default.fileExists(atPath: mechanicalRootURL.path)
    }

    static func == (lhs: YiacadProject, rhs: YiacadProject) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - Parsing

extension YiacadProject {
    init?(url: URL) {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        self.rootURL = url.deletingLastPathComponent()

        let rawSheets = json["sheets"] as? [[Any]] ?? []
        self.sheets = rawSheets.compactMap { $0.first as? String }
        self.designSettings = (json["board"] as? [String: Any])?["design_settings"] as? [String: Any]
        self.freecadDocuments = Self.discoverFreeCADDocuments(projectRoot: rootURL)
    }

    static func discoverFreeCADDocuments(projectRoot: URL) -> [FreeCADDocumentRef] {
        let mechanicalRoot = projectRoot.appendingPathComponent("mechanical", isDirectory: true)
        guard FileManager.default.fileExists(atPath: mechanicalRoot.path) else { return [] }

        let resolvedRoot = projectRoot.resolvingSymlinksInPath().standardizedFileURL

        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        let enumerator = FileManager.default.enumerator(
            at: mechanicalRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        let docs = (enumerator?.allObjects as? [URL] ?? []).compactMap { url -> FreeCADDocumentRef? in
            guard url.pathExtension.caseInsensitiveCompare("FCStd") == .orderedSame else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { return nil }
            let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
            let relative = relativePath(for: resolvedURL, root: resolvedRoot)
                ?? relativePath(for: url.standardizedFileURL, root: projectRoot.standardizedFileURL)
                ?? url.lastPathComponent
            return FreeCADDocumentRef(
                url: url,
                name: url.deletingPathExtension().lastPathComponent,
                relativePath: relative,
                lastModified: values?.contentModificationDate
            )
        }

        return docs.sorted { lhs, rhs in
            lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
        }
    }

    private static func relativePath(for url: URL, root: URL) -> String? {
        let rootComponents = root.pathComponents
        let urlComponents = url.pathComponents
        guard urlComponents.starts(with: rootComponents) else { return nil }
        let suffix = Array(urlComponents.dropFirst(rootComponents.count))
        guard !suffix.isEmpty else { return nil }
        return NSString.path(withComponents: suffix)
    }
}

// MARK: - Project manager

@MainActor
final class YiacadProjectManager: ObservableObject {
    @Published private(set) var currentProject: YiacadProject?
    @Published private(set) var recentProjects: [YiacadProject] = []

    private let recentsKey = "recentYiacadProjects"
    private let legacyRecentsKey = "recentKiCadProjects"
    private let maxRecents = 8

    init() {
        loadRecents()
    }

    func open(url: URL) {
        guard let project = YiacadProject(url: url) else { return }
        currentProject = project
        persist(url: url)
        loadRecents()
    }

    func close() {
        currentProject = nil
    }

    func rescanCurrentProject() {
        guard let currentURL = currentProject?.url else { return }
        currentProject = YiacadProject(url: currentURL)
    }

    private func persist(url: URL) {
        var paths = storedPaths()
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(maxRecents)), forKey: recentsKey)
    }

    private func loadRecents() {
        let paths = storedPaths()
        recentProjects = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .compactMap { YiacadProject(url: URL(fileURLWithPath: $0)) }
    }

    private func storedPaths() -> [String] {
        let stored = UserDefaults.standard.array(forKey: recentsKey) as? [String]
        if let stored { return stored }

        // Keep older installs working by migrating recents on the fly.
        let legacy = UserDefaults.standard.array(forKey: legacyRecentsKey) as? [String] ?? []
        if !legacy.isEmpty {
            UserDefaults.standard.set(legacy, forKey: recentsKey)
            UserDefaults.standard.removeObject(forKey: legacyRecentsKey)
        }
        return legacy
    }
}

// Transitional aliases for older views still named around KiCad-only terminology.
typealias KiCadProject = YiacadProject
typealias KiCadProjectManager = YiacadProjectManager
