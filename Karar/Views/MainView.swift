import SwiftUI

/// The main window (spec §3.2): installed models in the sidebar, the text on top, answers below.
struct MainView: View {
    @Bindable var app: AppModel
    @State private var engineVersion = ""

    var body: some View {
        NavigationSplitView {
            // Clicking empty space would deselect; there is always a model while any is installed.
            List(selection: Binding(get: { app.model }, set: { if let name = $0 { app.model = name } })) {
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
            ToolbarItem {
                Menu {
                    Picker("Model", selection: $app.model) {
                        ForEach(app.models, id: \.name) { Text($0.name).tag(Optional($0.name)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Label(app.model ?? "No model", systemImage: "cpu")
                        .labelStyle(.titleAndIcon)
                }
                .help("Model")
            }
            ToolbarItem {
                Menu {
                    Picker("Question set", selection: $app.preset) {
                        ForEach(Preset.all) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Label(app.preset.name, systemImage: "list.bullet.rectangle")
                        .labelStyle(.titleAndIcon)
                }
                .help("Question set")
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
                    editor
                        .padding([.horizontal, .top], 20)
                        .padding(.bottom, 16)
                    Divider()
                    results
                }
            }
        }
    }

    private var editor: some View {
        TextEditor(text: $app.text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            .overlay(alignment: .topLeading) {
                if app.text.isEmpty {
                    Text(app.preset.hint)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 15)   // 10 pt padding + the editor's 5 pt line-fragment inset
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 120, idealHeight: 160, maxHeight: 240)
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if app.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Answers appear here as you type.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Answers").font(.headline)
                        Spacer()
                        if app.isUpdating {
                            ProgressView().controlSize(.small)
                        } else if let result = app.result {
                            Text(verbatim: "\(result.model) · \(result.totalDuration / 1_000_000) ms")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let error = app.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        ForEach(app.rows) { row in
                            GridRow {
                                Text(row.label).foregroundStyle(.secondary)
                                Text(row.answer).bold()
                                ProgressView(value: row.sureness)
                                    .frame(minWidth: 120, maxWidth: .infinity)
                                Text("\(Int((row.sureness * 100).rounded()))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .gridColumnAlignment(.trailing)
                            }
                        }
                    }
                    .opacity(app.isUpdating ? 0.5 : 1)
                    .animation(.default, value: app.rows)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
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
