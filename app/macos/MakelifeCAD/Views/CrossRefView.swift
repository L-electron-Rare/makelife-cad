import SwiftUI

// MARK: - CrossRefRow

private struct CrossRefRow: Identifiable {
    let id: UUID
    let reference: String
    let value: String
    let footprintName: String     // from schematic (short form)
    let pcbFootprint: PCBFootprint?

    var isPlaced: Bool { pcbFootprint != nil }
}

// MARK: - CrossRefView

/// Shows the mapping between schematic components and their PCB footprints.
/// Displays placement status, position, and overall progress.
struct CrossRefView: View {
    @EnvironmentObject var schBridge: KiCadBridge
    @EnvironmentObject var pcbBridge: KiCadPCBBridge

    @State private var showOnlyUnplaced = false
    @State private var sortOrder: SortOrder = .byReference
    @State private var searchText = ""

    enum SortOrder: String, CaseIterable {
        case byReference = "Reference"
        case byStatus    = "Status"
    }

    // MARK: Derived data

    private var rows: [CrossRefRow] {
        let fpByRef = Dictionary(
            pcbBridge.footprints.map { ($0.reference, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return schBridge.components
            .filter { comp in
                let matchesSearch = searchText.isEmpty
                    || comp.reference.localizedCaseInsensitiveContains(searchText)
                    || comp.value.localizedCaseInsensitiveContains(searchText)
                let matchesFilter = !showOnlyUnplaced || fpByRef[comp.reference] == nil
                return matchesSearch && matchesFilter
            }
            .map { comp in
                let shortFP = comp.footprint.split(separator: ":").last.map(String.init) ?? comp.footprint
                return CrossRefRow(
                    id: comp.id,
                    reference: comp.reference,
                    value: comp.value,
                    footprintName: shortFP,
                    pcbFootprint: fpByRef[comp.reference]
                )
            }
            .sorted {
                switch sortOrder {
                case .byReference:
                    return $0.reference < $1.reference
                case .byStatus:
                    if $0.isPlaced != $1.isPlaced { return !$0.isPlaced }
                    return $0.reference < $1.reference
                }
            }
    }

    private var placedCount: Int {
        let refs = Set(pcbBridge.footprints.map(\.reference))
        return schBridge.components.filter { refs.contains($0.reference) }.count
    }
    private var total: Int { schBridge.components.count }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if schBridge.isLoaded {
                componentTable
            } else {
                emptyState
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .navigationTitle("Sch ↔ PCB")
    }

    // MARK: Header

    private var headerBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                // Status summary
                VStack(alignment: .leading, spacing: 1) {
                    Text("Placement progress")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text("\(placedCount) / \(total) components placed")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Toggle("Unplaced only", isOn: $showOnlyUnplaced)
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            // Progress bar
            ProgressView(value: total > 0 ? Double(placedCount) / Double(total) : 0)
                .tint(placedCount == total ? .green : .accentColor)
                .padding(.horizontal, 14)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Filter by reference or value…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.fill.tertiary)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .adaptiveSidebarBackground()
    }

    // MARK: Table

    private var componentTable: some View {
        Table(rows) {
            TableColumn("Ref") { row in
                Text(row.reference)
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundStyle(row.isPlaced ? Color.primary : Color.orange)
            }
            .width(min: 55, ideal: 75, max: 95)

            TableColumn("Value") { row in
                Text(row.value)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Footprint") { row in
                Text(row.footprintName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TableColumn("PCB Status") { row in
                if let fp = row.pcbFootprint {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(String(format: "(%.1f, %.1f) %@",
                                    fp.x, fp.y,
                                    fp.layer.contains("B.") ? "↓" : "↑"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Label("Not placed", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .width(min: 130, ideal: 160)

            TableColumn("Locate") { row in
                HStack(spacing: 4) {
                    Button {
                        NotificationCenter.default.post(
                            name: .makelifeHighlightInSchematic,
                            object: row.reference
                        )
                    } label: {
                        Image(systemName: "doc.richtext")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Locate \(row.reference) in Schematic")

                    if row.isPlaced {
                        Button {
                            NotificationCenter.default.post(
                                name: .makelifeHighlightInPCB,
                                object: row.reference
                            )
                        } label: {
                            Image(systemName: "cpu")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Locate \(row.reference) in PCB")
                    }
                }
            }
            .width(min: 60, ideal: 70, max: 80)
        }
        .tableStyle(.inset)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No schematic loaded")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Open a .kicad_sch to see component placement status")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
