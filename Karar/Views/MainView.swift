import SwiftUI
import AppKit

/// The main window (spec §3.2): installed models in the sidebar, the text on top, answers below.
struct MainView: View {
    @Bindable var app: AppModel
    @State private var showsDownloadSheet = false
    @State private var modelPendingDelete: String?
    @AppStorage("advanced") private var advanced = false
    /// Follows `advanced`, but only after `growWindowIfNeeded()`: the inspector crashes AppKit in
    /// narrower windows.
    @State private var showsInspector = false
    /// `.inspector` can't settle below ~960–980 pt of window width once Advanced is on (bisected in
    /// fix round 2); 1050 keeps margin. Shared by `.frame(minWidth:)` and `growWindowIfNeeded()` below.
    private static let advancedMinWidth: CGFloat = 1050

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
                    Picker("Question set", selection: Binding<Preset?>(
                        get: { app.isCustom ? nil : app.preset },
                        set: { choice in
                            if let choice {
                                app.preset = choice
                            } else {
                                app.useMyQuestions()
                                advanced = true
                            }
                        }
                    )) {
                        ForEach(Preset.all) { Text($0.name).tag(Optional($0)) }
                        Divider()
                        Text("My questions…").tag(Preset?.none)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Label(app.isCustom ? "My questions" : app.preset.name, systemImage: "list.bullet.rectangle")
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
            ToolbarItem {
                Toggle(isOn: $advanced) {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
                .toggleStyle(.button)
                .help("Edit the questions and inspect the response")
            }
        }
        // Only constrains a new window (launch, or a saved/injected frame smaller than this) — never
        // an already-open one; growWindowIfNeeded() below handles that case.
        .frame(minWidth: advanced ? Self.advancedMinWidth : 720, minHeight: 480)
        // `initial: true` also syncs showsInspector at launch — harmless no-op there since
        // `.frame(minWidth:)` already sized the window before it appeared.
        .onChange(of: advanced, initial: true) { _, newValue in
            if newValue {
                growWindowIfNeeded()
                showsInspector = true
            } else {
                showsInspector = false
            }
        }
        // Mirrors back into `advanced` if the inspector's own chrome ever dismisses it directly;
        // guarded so it can't ping-pong with the handler above.
        .onChange(of: showsInspector) { _, newValue in
            if newValue != advanced { advanced = newValue }
        }
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

    /// Grows an already-open window to `advancedMinWidth` before the inspector appears; SwiftUI
    /// can't resize an existing window, so this is AppKit, like `InspectorView`'s `NSPasteboard` use.
    private func growWindowIfNeeded() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }),
              window.frame.width < Self.advancedMinWidth else { return }
        var frame = window.frame
        frame.size.width = Self.advancedMinWidth
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        frame.origin.x = min(frame.origin.x, visible.maxX - frame.width)
        frame.origin.x = max(frame.origin.x, visible.minX)
        window.setFrame(frame, display: true, animate: false)
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
                    if advanced { cards } else { results }
                }
                .inspector(isPresented: $showsInspector) {
                    InspectorView(app: app)
                        .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
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
                    answersHeader
                    if let error = app.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                    if !app.questionErrors.isEmpty {
                        Label("Some questions are not valid. Turn on Advanced to see which.", systemImage: "exclamationmark.triangle")
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

    /// Advanced mode (spec §3.2): each question is an editable card with its raw answer.
    private var cards: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                answersHeader
                if let error = app.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                ForEach($app.questions) { $question in
                    QuestionCard(question: $question,
                                 answer: app.result?.answers[question.key],
                                 error: app.questionErrors[question.key]) {
                        app.questions.removeAll { $0.id == question.id }
                    }
                }
                .opacity(app.isUpdating ? 0.85 : 1)
                Button {
                    app.addQuestion()
                } label: {
                    Label("Add question", systemImage: "plus")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var answersHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(advanced ? "Questions" : "Answers").font(.headline)
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
