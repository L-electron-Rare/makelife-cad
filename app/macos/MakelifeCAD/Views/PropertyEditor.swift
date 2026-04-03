import SwiftUI

// MARK: - PropertyEditor

struct PropertyEditor: View {

    let item: SchItem
    var onApply: (String, String) -> Void

    // Editable field states — initialised from item
    @State private var editReference: String = ""
    @State private var editValue:     String = ""
    @State private var editFootprint: String = ""
    @State private var editText:      String = ""
    @State private var editX:         String = ""
    @State private var editY:         String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: iconForType(item.type))
                    .foregroundStyle(.blue)
                Text(titleForItem(item))
                    .font(.headline)
                    .lineLimit(1)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch item.type {
                    case .symbol:
                        symbolFields
                    case .wire:
                        wireFields
                    case .label:
                        labelFields
                    }
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { syncFields() }
        .onChange(of: item.id) { _ in syncFields() }
    }

    // MARK: - Symbol fields

    private var symbolFields: some View {
        Group {
            PropertyField(label: "Reference",
                          text: $editReference,
                          onCommit: { onApply("reference", editReference) })
            PropertyField(label: "Value",
                          text: $editValue,
                          onCommit: { onApply("value", editValue) })
            PropertyField(label: "Footprint",
                          text: $editFootprint,
                          onCommit: { onApply("footprint", editFootprint) })

            Divider()

            infoRow(label: "Library ID", value: item.libId ?? "\u{2014}")
            infoRow(label: "Position X", value: item.x.map { String(format: "%.1f mil", $0) } ?? "\u{2014}")
            infoRow(label: "Position Y", value: item.y.map { String(format: "%.1f mil", $0) } ?? "\u{2014}")
        }
    }

    // MARK: - Wire fields

    private var wireFields: some View {
        Group {
            infoRow(label: "Start X", value: item.x1.map { String(format: "%.1f mil", $0) } ?? "\u{2014}")
            infoRow(label: "Start Y", value: item.y1.map { String(format: "%.1f mil", $0) } ?? "\u{2014}")
            infoRow(label: "End X",   value: item.x2.map { String(format: "%.1f mil", $0) } ?? "\u{2014}")
            infoRow(label: "End Y",   value: item.y2.map { String(format: "%.1f mil", $0) } ?? "\u{2014}")
            infoRow(label: "Length",  value: wireLength(item).map { String(format: "%.1f mil", $0) } ?? "\u{2014}")
        }
    }

    // MARK: - Label fields

    private var labelFields: some View {
        Group {
            PropertyField(label: "Net name",
                          text: $editText,
                          onCommit: { onApply("text", editText) })

            Divider()

            infoRow(label: "Position X", value: item.x.map { String(format: "%.1f mil", $0) } ?? "\u{2014}")
            infoRow(label: "Position Y", value: item.y.map { String(format: "%.1f mil", $0) } ?? "\u{2014}")
        }
    }

    // MARK: - Helpers

    private func syncFields() {
        editReference = item.reference ?? ""
        editValue     = item.value     ?? ""
        editFootprint = item.footprint ?? ""
        editText      = item.text      ?? ""
        editX         = item.x.map { String(format: "%.1f", $0) } ?? ""
        editY         = item.y.map { String(format: "%.1f", $0) } ?? ""
    }

    private func iconForType(_ t: SchItemType) -> String {
        switch t {
        case .symbol: return "cpu"
        case .wire:   return "line.diagonal"
        case .label:  return "tag"
        }
    }

    private func titleForItem(_ item: SchItem) -> String {
        switch item.type {
        case .symbol: return item.reference ?? item.libId ?? "Symbol"
        case .wire:   return "Wire"
        case .label:  return item.text ?? "Label"
        }
    }

    private func wireLength(_ item: SchItem) -> Double? {
        guard let x1 = item.x1, let y1 = item.y1,
              let x2 = item.x2, let y2 = item.y2 else { return nil }
        return hypot(x2 - x1, y2 - y1)
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

// MARK: - PropertyField (labelled editable text field)

private struct PropertyField: View {
    let label:    String
    @Binding var text: String
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .onSubmit { onCommit() }
        }
    }
}
