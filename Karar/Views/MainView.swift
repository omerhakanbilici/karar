import SwiftUI

/// The main window (spec §3.2): installed models in the sidebar, the text on top, answers below.
struct MainView: View {
    @Bindable var app: AppModel
    @State private var engineVersion = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $app.model) {
                Section("Models") {
                    ForEach(app.models, id: \.name) { model in
                        LabeledContent(model.name,
                                       value: model.details.format == "router" ? "Router" : model.details.parameterSize)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { engineStatus }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Model", selection: $app.model) {
                    ForEach(app.models, id: \.name) { Text($0.name).tag(Optional($0.name)) }
                }
                Picker("Question set", selection: $app.preset) {
                    ForEach(Preset.all) { Text($0.name).tag($0) }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .task(id: app.daemon.state) {
            guard case .running = app.daemon.state else { return }
            await app.refreshModels()
            engineVersion = (try? await OllayaClient.local.version()) ?? ""
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await app.refreshModels() }
        }
    }

    @ViewBuilder private var detail: some View {
        switch app.daemon.state {
        case .starting:
            ProgressView("Starting Ollaya…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Ollaya is not running", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await app.daemon.start() } }
            }
        case .running:
            if app.models.isEmpty {
                ContentUnavailableView("No models yet", systemImage: "shippingbox",
                                       description: Text("Run `ollaya pull laya` in Terminal, then come back to Karar."))
            } else {
                VStack(spacing: 0) {
                    TextEditor(text: $app.text)
                        .font(.body)
                        .padding(8)
                        .frame(minHeight: 120, idealHeight: 160, maxHeight: 240)
                    Divider()
                    results
                }
            }
        }
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error = app.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else if app.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Type or paste text above to see the answers.")
                        .foregroundStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    ForEach(app.rows) { row in
                        GridRow {
                            Text(row.label).foregroundStyle(.secondary)
                            Text(row.answer).bold()
                            ProgressView(value: row.sureness).frame(width: 120)
                            Text(row.sureness, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                        }
                    }
                }
                .opacity(app.isUpdating ? 0.5 : 1)
                if let result = app.result {
                    Text("Answered by \(result.model) in \(result.totalDuration / 1_000_000) ms")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            if app.isUpdating {
                ProgressView().controlSize(.small).padding()
            }
        }
    }

    @ViewBuilder private var engineStatus: some View {
        if case .running(let owned) = app.daemon.state, !engineVersion.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ollaya \(engineVersion) · \(owned ? "started by Karar" : "already running")")
                if !Daemon.bundledVersion.isEmpty, "v\(engineVersion)" != Daemon.bundledVersion {
                    Label("Karar was built for Ollaya \(Daemon.bundledVersion)", systemImage: "exclamationmark.triangle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
