import SwiftUI
import UniformTypeIdentifiers

// MARK: - Modèle 2 scaffold — DocumentGroup-ready KiCad project document
//
// Activate by replacing WindowGroup in App.swift with:
//   DocumentGroup(viewing: KiCadProDocument.self) { file in
//       KiCadProDocumentView(document: file.document)
//   }
//
// Requires adding UTI declaration in Info.plist:
//   CFBundleDocumentTypes, LSItemContentTypes: cc.saillant.kicad-pro
// and registering the exported UTType below.

// MARK: - UTType extension

extension UTType {
    static let kicadProject = UTType(exportedAs: "cc.saillant.kicad-pro",
                                     conformingTo: .json)
}

// MARK: - Document model

struct KiCadProDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.kicadProject] }
    static var writableContentTypes: [UTType] { [] }  // read-only for now

    // Parsed fields
    var projectName: String = "Untitled"
    var schematicURL: URL?
    var pcbURL: URL?
    var sheets: [String] = []

    // Raw JSON for passthrough
    private var rawData: Data = Data()

    init() {}

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        rawData = data

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // KiCad .kicad_pro is a JSON file — extract project name from meta
            if let meta = json["meta"] as? [String: Any],
               let filename = meta["filename"] as? String {
                projectName = URL(fileURLWithPath: filename)
                    .deletingPathExtension().lastPathComponent
            }
            // Extract sheet names if present
            if let sheetsArr = json["sheets"] as? [[String: Any]] {
                sheets = sheetsArr.compactMap { $0["name"] as? String }
            }
        }

        // Derive companion file URLs from document URL (set post-init via fileURL)
        // Will be resolved in KiCadProDocumentView.onAppear using naming convention
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Read-only: return unchanged data
        return FileWrapper(regularFileWithContents: rawData)
    }
}

// MARK: - Document view scaffold

struct KiCadProDocumentView: View {
    let document: KiCadProDocument

    @StateObject private var schBridge   = KiCadBridge()
    @StateObject private var pcbBridge   = KiCadPCBBridge()
    @StateObject private var projectManager = YiacadProjectManager()

    // fileURL must be passed from the DocumentGroup binding (see usage comment above)
    @State private var documentURL: URL?

    @State private var activeTab: AppTab = .schematic
    @State private var selectedComponent: SchematicComponent?
    @State private var selectedFootprint: PCBFootprint?

    var body: some View {
        // Reuse ContentView structure — minimal adaptation needed
        Text("KiCad project: \(document.projectName)")
            .onAppear { loadProjectFiles() }
    }

    private func loadProjectFiles() {
        guard let url = documentURL else { return }
        let base = url.deletingPathExtension()
        let schURL = base.appendingPathExtension("kicad_sch")
        let pcbURL = base.appendingPathExtension("kicad_pcb")
        if FileManager.default.fileExists(atPath: schURL.path) {
            try? schBridge.openSchematic(path: schURL.path)
        }
        if FileManager.default.fileExists(atPath: pcbURL.path) {
            try? pcbBridge.openPCB(path: pcbURL.path)
        }
    }
}
