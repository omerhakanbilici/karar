import SwiftUI

/// The main window (spec §3.2): installed models in the sidebar, the text on top, answers below.
struct MainView: View {
    @Bindable var app: AppModel
    @State private var showsDownloadSheet = false
    @State private var modelPendingDelete: String?

    var body: some View {
        NavigationSplitView {
            // Clicking empty space would deselect; there is always a model while any is installed.
            List(selection: Binding(get: { app.model }, set: { if let name = $0 { app.model = name } })) {
                Section("Models") {
                    ForEach(app.models, id: \.name) { model in
                        LabeledContent(model.name,
                                       value: model.details.format == "router" ? "Router" : model.details.parameterSize)
                            .contextMenu {
                                Button("Delete…", role: .destructive) {
                                    modelPendingDelete = model.name
                                }
                            }
                    }
                    Button {
                        showsDownloadSheet = true
                    } label: {
                        Label("Download model…", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                if !app.pins.isEmpty {
                    Section("Pinned") {
                        ForEach(app.pins) { pin in
                            Button {
                                app.restore(pin)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pin.title)
                                        .lineLimit(1)
                                    Text(verbatim: "\(pin.setName) · \(pin.model)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .help(pin.rows.map { "\($0.label): \($0.answer)" }.joined(separator: "\n"))
                            .contextMenu {
                                Button("Remove") { app.unpin(pin) }
                            }
                        }
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
                    Divider()
                    Button("Download model…") { showsDownloadSheet = true }
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
            ToolbarItem {
                Button {
                    app.pin()
                } label: {
                    Label("Pin", systemImage: "pin")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(app.result == nil || app.isUpdating)
                .help("Pin the text and its answers to the sidebar (⌘↩)")
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .sheet(isPresented: $showsDownloadSheet) {
            DownloadSheet(app: app)
        }
        .confirmationDialog(
            "Delete \(modelPendingDelete ?? "")?",
            isPresented: Binding(get: { modelPendingDelete != nil }, set: { if !$0 { modelPendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: modelPendingDelete
        ) { name in
            Button("Delete", role: .destructive) {
                Task { await app.delete(name) }
            }
        } message: { _ in
            Text("It is removed from this Mac, also for the ollaya command line. You can download it again.")
        }
        .alert(
            "Could not delete the model",
            isPresented: Binding(get: { app.deleteError != nil }, set: { if !$0 { app.deleteError = nil } })
        ) {
            Button("OK") { app.deleteError = nil }
        } message: {
            Text(app.deleteError ?? "")
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
                ContentUnavailableView {
                    Label("No models", systemImage: "shippingbox")
                } actions: {
                    Button("Download model…") { showsDownloadSheet = true }
                }
            } else {
                VStack(spacing: 0) {
                    editor
                        .padding([.horizontal, .top], 20)
                    // Fixed height: the counter appearing, changing or turning into the warning never moves the layout.
                    tokenCounter
                        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .trailing)
                        .padding(.horizontal, 20)
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

    /// Spec §3.2: the engine's token count for the last answer, never an estimate; the warning in
    /// system orange when the text was cut (§5).
    @ViewBuilder private var tokenCounter: some View {
        if let result = app.result, let tokens = result.usage?.inputTokens {
            Group {
                if result.stateTruncated == true {
                    Label("Text too long for \(result.model): only the first part was read",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text("\(tokens.formatted()) tokens")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
            .opacity(app.isUpdating ? 0.5 : 1)
            .help(Self.tokenHelp(tokens: tokens, questions: result.answers.count))
        }
    }

    static func tokenHelp(tokens: Int, questions: Int) -> String {
        "\(tokens.formatted()) tokens read: your text plus each question's instructions and options, "
            + "counted once per question (\(questions) \(questions == 1 ? "question" : "questions"))."
    }

    @ViewBuilder private var engineStatus: some View {
        if case .running(let owned) = app.daemon.state, !app.engineVersion.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ollaya \(app.engineVersion) · \(owned ? "started by Karar" : "already running")")
                if !Daemon.bundledVersion.isEmpty, "v\(app.engineVersion)" != Daemon.bundledVersion {
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
