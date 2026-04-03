import SwiftUI
import UniformTypeIdentifiers

// MARK: - App entry point

@main
struct MakelifeCADApp: App {

    // Shared state — injected as environment objects into every scene
    @StateObject private var schBridge      = KiCadBridge()
    @StateObject private var pcbBridge      = KiCadPCBBridge()
    @StateObject private var editBridge     = KiCadSchEditBridge()
    @StateObject private var projectManager = YiacadProjectManager()
    @StateObject private var aiViewModel    = AppleIntelligenceViewModel()
    @StateObject private var fineFabVM      = FineFabViewModel()
    @StateObject private var freecadVM      = FreeCADViewModel()
    @StateObject private var githubVM       = GitHubLibraryViewModel()
    @StateObject private var commandRunner  = CommandRunner()

    // App-level UI state
    @State private var selectedComponent: SchematicComponent?
    @State private var selectedFootprint: PCBFootprint?
    @State private var showFileImporter  = false
    @State private var activeTab: AppTab = .schematic

    @StateObject private var pcbEditorVM = PCBEditorViewModel(bridge: KiCadPCBBridge())

    var body: some Scene {

        // ── MAIN WINDOW (Modèle 1 + existing) ──────────────────────────────
        WindowGroup {
            ContentView(
                schBridge: schBridge,
                pcbBridge: pcbBridge,
                projectManager: projectManager,
                aiViewModel: aiViewModel,
                fineFabVM: fineFabVM,
                freecadVM: freecadVM,
                githubVM: githubVM,
                selectedComponent: $selectedComponent,
                selectedFootprint: $selectedFootprint,
                showFileImporter: $showFileImporter,
                activeTab: $activeTab
            )
            .environmentObject(schBridge)
            .environmentObject(pcbBridge)
            .environmentObject(editBridge)
            .environmentObject(projectManager)
            .environmentObject(commandRunner)
            .environmentObject(aiViewModel)
            .environmentObject(fineFabVM)
            .environmentObject(freecadVM)
            .task {
                // Wire pcbEditorVM to the shared bridge (can't be done at @StateObject init time)
                pcbEditorVM.bridge = pcbBridge
                freecadVM.gatewayBaseURL = fineFabVM.baseURL
                freecadVM.attach(project: projectManager.currentProject)
                await freecadVM.refreshAll()
            }
            .onChange(of: projectManager.currentProject?.url) { _, _ in
                guard let project = projectManager.currentProject else {
                    freecadVM.attach(project: nil)
                    return
                }
                if project.hasSchematic {
                    try? schBridge.openSchematic(path: project.schematicURL.path)
                }
                if project.hasPCB {
                    try? pcbBridge.openPCB(path: project.pcbURL.path)
                }
                freecadVM.attach(project: project)
                Task { await freecadVM.refreshAll() }
            }
            .onChange(of: projectManager.currentProject?.schematicURL) { _, url in
                fineFabVM.schematicURL = url
            }
            .onChange(of: fineFabVM.baseURL) { _, newValue in
                freecadVM.gatewayBaseURL = newValue
                Task { await freecadVM.refreshAll() }
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { showFileImporter = true }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Open Project…") { openProjectPanel() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save PCB…") { savePCB() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save Schematic") { trySaveSchematic() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                    .disabled(!editBridge.isDirty)
                Button("Import Netlist…") { importNetlist() }
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
                Button("Finish Zone") { pcbEditorVM.commitZone() }
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
        }

        // ── MODÈLE 1 — Utility windows ─────────────────────────────────────

        Window("BOM", id: "bom") {
            BOMView()
                .environmentObject(schBridge)
                .environmentObject(pcbBridge)
        }
        .defaultSize(width: 700, height: 480)

        Window("Terminal", id: "terminal") {
            TerminalWindowView()
                .environmentObject(commandRunner)
                .environmentObject(projectManager)
        }
        .defaultSize(width: 840, height: 420)

        Window("AI Chat", id: "ai-chat") {
            AIDetailView(aiVM: aiViewModel, fineFabVM: fineFabVM, provider: .onDevice)
                .frame(minWidth: 440, minHeight: 480)
        }
        .defaultSize(width: 500, height: 600)

        Window("Fab Preview", id: "fab-preview") {
            FabPreviewView()
                .environmentObject(pcbBridge)
        }
        .defaultSize(width: 780, height: 520)

        Window("Git Diff", id: "git-diff") {
            GitDiffView()
                .environmentObject(schBridge)
                .environmentObject(projectManager)
        }
        .defaultSize(width: 620, height: 440)

        Window("Sch ↔ PCB", id: "cross-ref") {
            CrossRefView()
                .environmentObject(schBridge)
                .environmentObject(pcbBridge)
        }
        .defaultSize(width: 660, height: 440)

        Window("Design Notes", id: "annotations") {
            AnnotationsView()
        }
        .defaultSize(width: 500, height: 420)

        // ── MODÈLE 3 — Document windows (auto-contained bridge per window) ──
        // Usage: openWindow(id: "sch-doc", value: url)
        //        openWindow(id: "pcb-doc", value: url)

        WindowGroup("Schematic", id: "sch-doc", for: URL.self) { $url in
            if let url { SchematicDocumentView(fileURL: url) }
        }
        .defaultSize(width: 900, height: 600)

        WindowGroup("PCB", id: "pcb-doc", for: URL.self) { $url in
            if let url { PCBDocumentView(fileURL: url) }
        }
        .defaultSize(width: 900, height: 600)

        // ── MODÈLE 2 — DocumentGroup scaffold (not yet active) ─────────────
        // To enable: uncomment and remove the WindowGroup above.
        //
        // DocumentGroup(viewing: KiCadProDocument.self) { file in
        //     KiCadProDocumentView(document: file.document)
        // }
    }

    // MARK: - Project operations

    @MainActor
    func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open KiCad Project"
        panel.message = "Select a .kicad_pro project file"
        if let type = UTType(filenameExtension: "kicad_pro") {
            panel.allowedContentTypes = [type]
        }
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            projectManager.open(url: url)
        }
    }

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
        panel.message = "Select a netlist JSON file"
        if panel.runModal() == .OK, let url = panel.url,
           let json = try? String(contentsOf: url, encoding: .utf8) {
            _ = pcbEditorVM.bridge.importNetlist(json)
        }
    }

    @State private var currentSchFilePath: String?

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
    case freecad   = "FreeCAD"
    case ai        = "AI"
    case github    = "Library"

    var systemImage: String {
        switch self {
        case .schematic: return "doc.richtext"
        case .pcb:       return "cpu"
        case .viewer3d:  return "view.3d"
        case .freecad:   return "cube.transparent"
        case .ai:        return "sparkles"
        case .github:    return "books.vertical"
        }
    }

    var isCadTab: Bool {
        switch self {
        case .schematic, .pcb, .viewer3d: return true
        case .freecad, .ai, .github: return false
        }
    }
}

extension AppTab {
    var checkLabel: String {
        switch self {
        case .schematic:          return "Run ERC"
        case .pcb, .viewer3d:     return "Run DRC"
        case .freecad, .ai, .github: return ""
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var schBridge: KiCadBridge
    @ObservedObject var pcbBridge: KiCadPCBBridge
    @ObservedObject var projectManager: YiacadProjectManager
    @ObservedObject var aiViewModel: AppleIntelligenceViewModel
    @ObservedObject var fineFabVM: FineFabViewModel
    @ObservedObject var freecadVM: FreeCADViewModel
    @ObservedObject var githubVM: GitHubLibraryViewModel
    @Binding var selectedComponent: SchematicComponent?
    @Binding var selectedFootprint: PCBFootprint?
    @Binding var showFileImporter: Bool
    @Binding var activeTab: AppTab

    @State private var activeLayerId: Int?
    @State private var showViolations = false
    @State private var aiProvider: AIProvider = .onDevice
    @State private var showPalette = false

    // Modèle 1 + 3 window opening
    @Environment(\.openWindow) private var openWindow

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
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .alert("Error", isPresented: .constant(currentError != nil), actions: {
            Button("OK") { }
        }, message: {
            Text(currentError ?? "")
        })
        // ── Command Palette overlay ────────────────────────────────────────
        .commandPalette(isPresented: $showPalette, items: buildPaletteItems())
        // ── AI auto-context: inject component list when schematic changes ──
        .onChange(of: schBridge.components.count) { _, _ in
            let components = schBridge.components
            let summary: String? = components.isEmpty ? nil :
                "Active schematic — \(components.count) components:\n" +
                components.map { "\($0.reference): \($0.value) [\($0.footprint)]" }
                          .joined(separator: "\n")
            aiViewModel.schematicSummary = summary
            fineFabVM.schematicContext   = summary
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            ProjectPanel(
                manager: projectManager,
                onOpenSchematic: { url in
                    activeTab = .schematic
                    try? schBridge.openSchematic(path: url.path)
                },
                onOpenPCB: { url in
                    activeTab = .pcb
                    try? pcbBridge.openPCB(path: url.path)
                }
            )

            Picker("", selection: $activeTab) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
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
                        .font(.caption).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center).padding()
                    Spacer()
                }
            case .freecad:
                FreeCADSidebarView(viewModel: freecadVM)
            case .ai:
                AISidebarView(aiVM: aiViewModel, fineFabVM: fineFabVM, provider: $aiProvider)
            case .github:
                GitHubSidebarView(vm: githubVM)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch activeTab {
        case .freecad:
            FreeCADDetailView(viewModel: freecadVM)
        case .ai:
            AIDetailView(aiVM: aiViewModel, fineFabVM: fineFabVM, provider: aiProvider)
        case .github:
            GitHubDetailView(entry: githubVM.selectedEntry)
        default:
            cadDetail
        }
    }

    private var cadDetail: some View {
        VSplitView {
            Group {
                switch activeTab {
                case .schematic:
                    SchematicView(bridge: schBridge, selectedComponent: $selectedComponent)
                case .pcb:
                    PCBView(bridge: pcbBridge, activeLayerId: $activeLayerId)
                case .viewer3d:
                    PCB3DView(bridge: pcbBridge)
                default:
                    EmptyView()
                }
            }
            .frame(minHeight: 300)

            if showViolations {
                violationsPanel.frame(minHeight: 120, idealHeight: 200, maxHeight: 320)
            }
        }
    }

    @ViewBuilder
    private var violationsPanel: some View {
        switch activeTab {
        case .schematic:        ViolationsView(kind: .erc(schBridge))
        case .pcb, .viewer3d:   ViolationsView(kind: .drc(pcbBridge))
        default:                EmptyView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // Open file
        ToolbarItem(placement: .primaryAction) {
            Button {
                if activeTab == .freecad {
                    freecadVM.openSelectedInFreeCAD()
                } else {
                    showFileImporter = true
                }
            } label: {
                Label(activeTab == .freecad ? "Open in FreeCAD" : "Open", systemImage: "folder.badge.plus")
            }
            .help(activeTab == .freecad ? "Open selected `.FCStd` in FreeCAD" : (activeTab == .schematic ? "Open .kicad_sch" : "Open .kicad_pcb"))
        }

        // Close file (CAD tabs only)
        ToolbarItem {
            if activeTab.isCadTab {
                Button {
                    switch activeTab {
                    case .schematic:
                        schBridge.close(); selectedComponent = nil
                    case .pcb, .viewer3d:
                        pcbBridge.closePCB(); selectedFootprint = nil; activeLayerId = nil
                    default: break
                    }
                } label: {
                    Label("Close", systemImage: "xmark.circle")
                }
                .help("Close current file")
                .disabled(activeTab == .schematic ? !schBridge.isLoaded : !pcbBridge.isLoaded)
            }
        }

        // 3D toggle
        ToolbarItem {
            if activeTab == .pcb && pcbBridge.isLoaded {
                Button { activeTab = .viewer3d } label: {
                    Label("3D", systemImage: "view.3d")
                }
                .help("3D viewer")
            }
        }

        ToolbarItemGroup {
            if activeTab == .freecad {
                Button {
                    Task { await freecadVM.exportSelected(format: .step) }
                } label: {
                    Label("STEP", systemImage: "shippingbox")
                }
                .disabled(freecadVM.selectedDocument == nil || freecadVM.isExporting)

                Button {
                    Task { await freecadVM.exportSelected(format: .stl) }
                } label: {
                    Label("STL", systemImage: "shippingbox")
                }
                .disabled(freecadVM.selectedDocument == nil || freecadVM.isExporting)

                Button {
                    freecadVM.refreshDocuments()
                } label: {
                    Label("Refresh Files", systemImage: "arrow.clockwise")
                }

                Button {
                    Task { await freecadVM.refreshAll(forceGatewayProbe: true) }
                } label: {
                    Label("Validate Runtime", systemImage: "checkmark.shield")
                }
            }
        }

        // ERC/DRC toggle (CAD tabs)
        ToolbarItem {
            if activeTab.isCadTab {
                Button { showViolations.toggle() } label: {
                    Label(activeTab.checkLabel,
                          systemImage: showViolations ? "exclamationmark.triangle.fill"
                                                      : "exclamationmark.triangle")
                }
                .help(showViolations ? "Hide violations" : "Show \(activeTab.checkLabel)")
            }
        }

        // ── Modèle 1 — Detach / utility window buttons ────────────────────

        ToolbarItem {
            if activeTab == .schematic && schBridge.isLoaded {
                // Open BOM window
                Button {
                    openWindow(id: "bom")
                } label: {
                    Label("BOM", systemImage: "tablecells")
                }
                .help("Open Bill of Materials (⌘⇧B)")
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }

        ToolbarItemGroup {
            if activeTab == .pcb && pcbBridge.isLoaded {
                Button { openWindow(id: "fab-preview") } label: {
                    Label("Fab Preview", systemImage: "eye.square")
                }
                .help("Gerber-style fab preview")
            }
            if activeTab == .schematic && schBridge.isLoaded {
                Button { openWindow(id: "git-diff") } label: {
                    Label("Git Diff", systemImage: "arrow.triangle.branch")
                }
                .help("Schematic diff vs HEAD")
            }
        }

        ToolbarItemGroup {
            Button {
                openWindow(id: "terminal")
            } label: {
                Label("Terminal", systemImage: "terminal")
            }
            .help("Open terminal (⌘⇧T)")
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button { showPalette.toggle() } label: {
                Label("Command Palette", systemImage: "magnifyingglass")
            }
            .help("Command palette (⌘P)")
            .keyboardShortcut("p", modifiers: .command)
        }

        // ── Modèle 3 — Detach schematic/PCB in own window ─────────────────

        ToolbarItemGroup {
            if activeTab == .schematic, let url = projectManager.currentProject?.schematicURL {
                Button {
                    openWindow(id: "sch-doc", value: url)
                } label: {
                    Label("Detach", systemImage: "macwindow.badge.plus")
                }
                .help("Open schematic in separate window")
            }

            if activeTab == .pcb, let url = projectManager.currentProject?.pcbURL {
                Button {
                    openWindow(id: "pcb-doc", value: url)
                } label: {
                    Label("Detach", systemImage: "macwindow.badge.plus")
                }
                .help("Open PCB in separate window")
            }
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
        case .schematic:       return schBridge.errorMessage
        case .pcb, .viewer3d:  return pcbBridge.errorMessage
        case .freecad, .ai, .github:     return nil
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                if url.pathExtension.lowercased() == "kicad_pcb" {
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
            print("[MakelifeCAD] import error: \(error.localizedDescription)")
        }
    }

    // MARK: - Command Palette items

    private func buildPaletteItems() -> [PaletteItem] {
        var items: [PaletteItem] = []

        // Navigation — tabs
        for tab in AppTab.allCases {
            let t = tab
            items.append(PaletteItem(
                title: "Go to \(t.rawValue)",
                subtitle: "Switch active tab",
                icon: t.systemImage,
                category: "Navigation"
            ) { activeTab = t })
        }

        // Windows (Modèle 1)
        items.append(PaletteItem(title: "Open BOM", subtitle: "Bill of Materials window",
                                 icon: "tablecells", category: "Windows",
                                 badge: "⌘⇧B") { openWindow(id: "bom") })
        items.append(PaletteItem(title: "Open Terminal", subtitle: "PlatformIO / ESP-IDF",
                                 icon: "terminal", category: "Windows",
                                 badge: "⌘⇧T") { openWindow(id: "terminal") })
        items.append(PaletteItem(title: "Open AI Chat", subtitle: "Detached AI assistant",
                                 icon: "sparkles", category: "Windows") { openWindow(id: "ai-chat") })
        items.append(PaletteItem(title: "Fab Preview", subtitle: "Gerber-style PCB visualization",
                                 icon: "eye.square", category: "Windows") { openWindow(id: "fab-preview") })
        items.append(PaletteItem(title: "Git Diff", subtitle: "Schematic changes vs HEAD",
                                 icon: "arrow.triangle.branch", category: "Windows") { openWindow(id: "git-diff") })
        items.append(PaletteItem(title: "Sch ↔ PCB", subtitle: "Component placement cross-reference",
                                 icon: "arrow.left.arrow.right", category: "Windows") { openWindow(id: "cross-ref") })
        items.append(PaletteItem(title: "Design Notes", subtitle: "TODOs, warnings, bugs for this design",
                                 icon: "note.text", category: "Windows") { openWindow(id: "annotations") })

        // Files
        items.append(PaletteItem(title: "Open File…", subtitle: ".kicad_sch / .kicad_pcb",
                                 icon: "folder.badge.plus", category: "Files",
                                 badge: "⌘O") { showFileImporter = true })
        items.append(PaletteItem(title: "Open Project…", subtitle: ".kicad_pro project",
                                 icon: "folder.badge.gearshape", category: "Files",
                                 badge: "⇧⌘O") { /* triggers App method via notification */ })

        // Actions — schematic
        if schBridge.isLoaded {
            items.append(PaletteItem(title: "Run ERC", subtitle: "Electrical Rules Check",
                                     icon: "exclamationmark.triangle", category: "Actions") {
                activeTab = .schematic
                showViolations = true
            })
            items.append(PaletteItem(title: "Close Schematic", subtitle: "",
                                     icon: "xmark.circle", category: "Actions",
                                     isDestructive: true) {
                schBridge.close(); selectedComponent = nil
            })
            if let url = projectManager.currentProject?.schematicURL {
                items.append(PaletteItem(title: "Detach Schematic", subtitle: "Open in new window",
                                         icon: "macwindow.badge.plus", category: "Actions") {
                    openWindow(id: "sch-doc", value: url)
                })
            }
        }

        // Actions — PCB
        if pcbBridge.isLoaded {
            items.append(PaletteItem(title: "Run DRC", subtitle: "Design Rules Check",
                                     icon: "exclamationmark.triangle", category: "Actions") {
                activeTab = .pcb
                showViolations = true
            })
            items.append(PaletteItem(title: "Switch to 3D View", subtitle: "",
                                     icon: "view.3d", category: "Actions") { activeTab = .viewer3d })
            items.append(PaletteItem(title: "Close PCB", subtitle: "",
                                     icon: "xmark.circle", category: "Actions",
                                     isDestructive: true) {
                pcbBridge.closePCB(); selectedFootprint = nil; activeLayerId = nil
            })
            if let url = projectManager.currentProject?.pcbURL {
                items.append(PaletteItem(title: "Detach PCB", subtitle: "Open in new window",
                                         icon: "macwindow.badge.plus", category: "Actions") {
                    openWindow(id: "pcb-doc", value: url)
                })
            }
        }

        // Layers (quick toggle)
        for layer in pcbBridge.layers where pcbBridge.isLoaded {
            let lid = layer.id
            items.append(PaletteItem(
                title: (layer.visible ? "Hide " : "Show ") + layer.name,
                subtitle: "PCB layer",
                icon: layer.visible ? "eye.slash" : "eye",
                category: "Layers"
            ) { pcbBridge.toggleLayerVisibility(id: lid) })
        }

        // Components (jump)
        for comp in schBridge.components where schBridge.isLoaded {
            let c = comp
            items.append(PaletteItem(
                title: "\(c.reference)  \(c.value)",
                subtitle: c.footprint,
                icon: c.kind == .ic ? "cpu" : "circle.fill",
                category: "Components"
            ) {
                activeTab = .schematic
                selectedComponent = c
            })
        }

        // Recent projects
        for project in projectManager.recentProjects {
            let p = project
            items.append(PaletteItem(
                title: p.name,
                subtitle: p.rootURL.path,
                icon: "folder",
                category: "Recent Projects"
            ) { projectManager.open(url: p.url) })
        }

        return items
    }
}
