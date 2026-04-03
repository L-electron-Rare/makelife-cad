import SwiftUI
import UniformTypeIdentifiers

// MARK: - App entry point

@main
struct MakelifeCADApp: App {

    @StateObject private var schBridge   = KiCadBridge()
    @StateObject private var pcbBridge   = KiCadPCBBridge()
    @StateObject private var editBridge  = KiCadSchEditBridge()
    @State private var selectedComponent: SchematicComponent?
    @State private var selectedFootprint: PCBFootprint?
    @State private var showFileImporter  = false
    @State private var activeTab: AppTab = .schematic
    @State private var currentSchFilePath: String? = nil

    // PCB editor ViewModel — created once and kept alive for the session.
    @StateObject private var pcbEditorVM = PCBEditorViewModel(bridge: KiCadPCBBridge())

    var body: some Scene {
        WindowGroup {
            ContentView(
                schBridge: schBridge,
                pcbBridge: pcbBridge,
                selectedComponent: $selectedComponent,
                selectedFootprint: $selectedFootprint,
                showFileImporter: $showFileImporter,
                activeTab: $activeTab
            )
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open\u{2026}") {
                    showFileImporter = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Edit") {
                Button("Undo") { pcbEditorVM.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { pcbEditorVM.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                Divider()
                Button("Delete") { pcbEditorVM.deleteSelected() }
                    .keyboardShortcut(.delete, modifiers: [])
                Divider()
                Button("Finish Zone") {
                    pcbEditorVM.commitZone()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(pcbEditorVM.activeTool != .zone)
                Divider()
                Button("Escape Tool") {
                    pcbEditorVM.activeTool = .select
                    pcbEditorVM.trackStart = nil
                    pcbEditorVM.zonePoints = []
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save PCB\u{2026}") { savePCB() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save Schematic") { trySaveSchematic() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                    .disabled(!editBridge.isDirty)
                Button("Import Netlist\u{2026}") { importNetlist() }
            }
        }
    }

    // MARK: - PCB file operations

    @MainActor
    func savePCB() {
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: "kicad_pcb") {
            panel.allowedContentTypes = [type]
        }
        panel.nameFieldStringValue = "board.kicad_pcb"
        if panel.runModal() == .OK, let url = panel.url {
            pcbEditorVM.save(to: url.path)
        }
    }

    @MainActor
    func importNetlist() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Select a netlist JSON file (from schematic export)"
        if panel.runModal() == .OK, let url = panel.url,
           let json = try? String(contentsOf: url, encoding: .utf8) {
            _ = pcbEditorVM.bridge.importNetlist(json)
        }
    }

    @MainActor
    func trySaveSchematic() {
        guard let path = currentSchFilePath else {
            let panel = NSSavePanel()
            if let uti = UTType(filenameExtension: "kicad_sch") {
                panel.allowedContentTypes = [uti]
            }
            panel.nameFieldStringValue = "untitled.kicad_sch"
            if panel.runModal() == .OK, let url = panel.url {
                currentSchFilePath = url.path
                try? editBridge.save(path: url.path)
            }
            return
        }
        try? editBridge.save(path: path)
    }
}

// MARK: - Tab model

enum AppTab: String, CaseIterable {
    case schematic = "Schematic"
    case pcb       = "PCB"
    case viewer3d  = "3D"

    var systemImage: String {
        switch self {
        case .schematic: return "doc.richtext"
        case .pcb:       return "cpu"
        case .viewer3d:  return "view.3d"
        }
    }
}

// MARK: - Violations panel visibility

extension AppTab {
    var checkLabel: String {
        switch self {
        case .schematic: return "Run ERC"
        case .pcb:       return "Run DRC"
        case .viewer3d:  return "Run DRC"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var schBridge: KiCadBridge
    @ObservedObject var pcbBridge: KiCadPCBBridge
    @Binding var selectedComponent: SchematicComponent?
    @Binding var selectedFootprint: PCBFootprint?
    @Binding var showFileImporter: Bool
    @Binding var activeTab: AppTab

    @State private var activeLayerId: Int? = nil
    @State private var showViolations: Bool = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .toolbar { toolbarItems }
        }
        .navigationTitle("MakelifeCAD")
        .frame(minWidth: 900, minHeight: 600)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert("Error", isPresented: .constant(currentError != nil), actions: {
            Button("OK") { }
        }, message: {
            Text(currentError ?? "")
        })
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $activeTab) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch activeTab {
            case .schematic:
                ComponentList(bridge: schBridge, selectedComponent: $selectedComponent)
            case .pcb:
                LayerPanel(bridge: pcbBridge,
                           activeLayerId: $activeLayerId,
                           selectedFootprint: $selectedFootprint)
            case .viewer3d:
                VStack {
                    Spacer()
                    Text("3D layer controls\nare in the viewer panel")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        VSplitView {
            // Main viewer — takes most space
            Group {
                switch activeTab {
                case .schematic:
                    SchematicView(bridge: schBridge, selectedComponent: $selectedComponent)
                case .pcb:
                    PCBView(bridge: pcbBridge, activeLayerId: $activeLayerId)
                case .viewer3d:
                    PCB3DView(bridge: pcbBridge)
                }
            }
            .frame(minHeight: 300)

            // Violations panel — collapsible bottom strip
            if showViolations {
                violationsPanel
                    .frame(minHeight: 120, idealHeight: 200, maxHeight: 320)
            }
        }
    }

    @ViewBuilder
    private var violationsPanel: some View {
        switch activeTab {
        case .schematic:
            ViolationsView(kind: .erc(schBridge))
        case .pcb, .viewer3d:
            ViolationsView(kind: .drc(pcbBridge))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showFileImporter = true
            } label: {
                Label("Open", systemImage: "folder.badge.plus")
            }
            .help(activeTab == .schematic ? "Open .kicad_sch file" : "Open .kicad_pcb file")
        }

        ToolbarItem {
            Button {
                switch activeTab {
                case .schematic:
                    schBridge.close()
                    selectedComponent = nil
                case .pcb, .viewer3d:
                    pcbBridge.closePCB()
                    selectedFootprint = nil
                    activeLayerId = nil
                }
            } label: {
                Label("Close", systemImage: "xmark.circle")
            }
            .help("Close current file")
            .disabled(activeTab == .schematic ? !schBridge.isLoaded : !pcbBridge.isLoaded)
        }

        ToolbarItem {
            if activeTab == .pcb && pcbBridge.isLoaded {
                Button {
                    activeTab = .viewer3d
                } label: {
                    Label("3D View", systemImage: "view.3d")
                }
                .help("Switch to 3D viewer")
            }
        }

        ToolbarItem {
            Button {
                showViolations.toggle()
            } label: {
                Label(activeTab.checkLabel,
                      systemImage: showViolations ? "exclamationmark.triangle.fill"
                                                  : "exclamationmark.triangle")
            }
            .help(showViolations ? "Hide violations panel" : "Show \(activeTab.checkLabel) panel")
        }
    }

    // MARK: - Helpers

    private var allowedTypes: [UTType] {
        var types: [UTType] = []
        if let sch = UTType(filenameExtension: "kicad_sch") { types.append(sch) }
        if let pcb = UTType(filenameExtension: "kicad_pcb") { types.append(pcb) }
        return types.isEmpty ? [.data] : types
    }

    private var currentError: String? {
        switch activeTab {
        case .schematic:        return schBridge.errorMessage
        case .pcb, .viewer3d:  return pcbBridge.errorMessage
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let ext = url.pathExtension.lowercased()
            do {
                if ext == "kicad_pcb" {
                    activeTab = .pcb
                    try pcbBridge.openPCB(path: url.path)
                } else {
                    activeTab = .schematic
                    try schBridge.openSchematic(path: url.path)
                }
            } catch {
                print("[MakelifeCAD] open failed: \(error.localizedDescription)")
            }

        case .failure(let error):
            print("[MakelifeCAD] file import error: \(error.localizedDescription)")
        }
    }
}
