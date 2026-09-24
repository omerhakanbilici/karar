import SwiftUI
import AppKit

/// Advanced mode's inspector (spec §3.2): which model answered and by which route, how long it
/// took, how many tokens it read, and the response itself.
struct InspectorView: View {
    let app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let result = app.result {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                        row("Model", result.model)
                        if let routing = result.routing {
                            GridRow {
                                label("Route")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(routing.route)
                                    Text(routing.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        row("Total", Self.milliseconds(result.totalDuration))
                        if let eval = result.evalDuration { row("Eval", Self.milliseconds(eval)) }
                        if let tokens = result.usage?.inputTokens { row("Input tokens", tokens.formatted()) }
                    }
                } else {
                    Text("No response yet.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Copy JSON") {
                        if let result = app.result { Self.copy(OrderedJSON.pretty(result.json)) }
                    }
                    .disabled(app.result == nil)
                    Button("Copy as curl") {
                        if let body = app.requestBody { Self.copy(OllayaClient.local.curl(body: body)) }
                    }
                    .disabled(app.requestBody == nil)
                }
                if let result = app.result {
                    Text(OrderedJSON.pretty(result.json))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quinary, in: .rect(cornerRadius: 6))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    @ViewBuilder private func row(_ name: String, _ value: String) -> some View {
        GridRow {
            label(name)
            Text(value)
                .monospacedDigit()
                .textSelection(.enabled)
        }
    }

    static func milliseconds(_ nanoseconds: Int64) -> String {
        String(format: "%.1f ms", Double(nanoseconds) / 1_000_000)
    }

    private static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
