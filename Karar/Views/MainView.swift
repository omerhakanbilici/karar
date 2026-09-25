import SwiftUI
import AppKit

/// The main window (spec §3.2): installed models in the sidebar, the text on top, answers below.
struct MainView: View {
    @Bindable var app: AppModel
    @Environment(\.openURL) private var openURL
    @State private var showsDownloadSheet = false
    @State private var modelPendingDelete: String?
    @AppStorage("advanced") private var advanced = false
    /// `.inspector` can't settle below ~960–980 pt of window width once Advanced is on (bisected in
    /// fix round 2); 1050 keeps margin. Shared by `.frame(minWidth:)` and `growWindowIfNeeded()` below.
    private static let advancedMinWidth: CGFloat = 1050

    var body: some View {
        NavigationSplitView {
            // A plain Binding(app.model): clicking empty space would otherwise deselect, and the
            // model can be nil on its own (missingModel) without the list clearing the row.
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
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .help("Download model… (⇧⌘D)")
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
                            .accessibilityIdentifier("pinnedResult")
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
                    Label(app.model ?? "Choose a model", systemImage: "cpu")
                        .labelStyle(.titleAndIcon)
                }
                .help("Model")
            }
            ToolbarItem {
                Menu {
                    Picker("Question set", selection: Binding<Preset?>(
                        get: { app.isCustom ? nil : app.preset },
                        set: { if let choice = $0 { app.preset = choice } }
                    )) {
                        ForEach(Preset.all) { Text($0.name).tag(Optional($0)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    Divider()
                    // A button, not a Picker tag: re-picking an already-selected tag fires no setter,
                    // so a tagged "My questions…" row silently no-ops when it's already selected.
                    Button("My questions…") {
                        app.useMyQuestions()
                        advancedBinding.wrappedValue = true
                    }
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
                .accessibilityIdentifier("pin")
                .disabled(app.result == nil || app.isUpdating)
                .help("Pin the text and its answers to the sidebar (⌘↩)")
            }
            ToolbarItem {
                Toggle(isOn: advancedBinding) {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
                .toggleStyle(.button)
                .keyboardShortcut("i", modifiers: [.command, .option])
                .help("Edit the questions and inspect the response (⌥⌘I)")
            }
        }
        // Only constrains a new window (launch, or a saved/injected frame smaller than this) — never
        // an already-open one; growWindowIfNeeded() below handles that case.
        .frame(minWidth: advanced ? Self.advancedMinWidth : 720, minHeight: 480)
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

    /// Single source of truth for Advanced/the inspector: growing the window happens here, once,
    /// before turning either on — whichever side (toolbar Toggle or the inspector's own chrome) flips it.
    private var advancedBinding: Binding<Bool> {
        Binding(get: { advanced }, set: { newValue in
            if newValue { growWindowIfNeeded() }
            advanced = newValue
        })
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
        if app.daemon.state == .starting {
            ProgressView("Starting Ollaya…")
        } else if app.models.isEmpty {
            // Empty models + running + no error is always onboarding or the startup spinner, never
            // a reachable-but-empty state, so there is only this one description, no action.
            VStack(spacing: 0) {
                banner
                ContentUnavailableView {
                    Label("No models", systemImage: "shippingbox")
                } description: {
                    Text("Installed models appear here once Karar can reach Ollaya.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                // Inside the view that carries .inspector, and with a line-limited message: a
                // height-for-width text in a top safe-area inset loops AppKit's constraint passes
                // (crash) and misplaces the content.
                banner
                editor
                    .padding([.horizontal, .top], 20)
                // Always reserve 30 pt for the counter or warning.
                tokenCounter
                    .padding(.horizontal, 20)
                Divider()
                if advanced { cards } else { results }
            }
            .inspector(isPresented: advancedBinding) {
                InspectorView(app: app)
                    .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
            }
        }
    }

    /// Spec §5: the engine failed (message + Restart), the port is taken (how to free it), or the
    /// installed models can't be listed. Retrying is always the user's click.
    @ViewBuilder private var banner: some View {
        switch app.daemon.state {
        case .portInUse:
            ErrorBanner(title: "Port 11435 is in use by another program",
                        message: "Ollaya needs this port. Quit the program that uses it, then click Try Again. "
                            + "To see which program it is, run lsof -i :11435 in Terminal.") {
                Button("Try Again") { Task { await app.daemon.start() } }
            }
        case .failed(let message):
            ErrorBanner(title: "Ollaya is not running", message: message) {
                Button("Show Log") { openURL(Daemon.logURL) }
                Button("Restart") { Task { await app.daemon.start() } }
            }
        case .running where app.modelsError != nil:
            ErrorBanner(title: "Could not load the installed models", message: app.modelsError ?? "") {
                // An adopted CLI daemon that died needs re-adopting or relaunching, not just a
                // refresh; start() is a no-op while Karar's own daemon is already running.
                Button("Try Again") { Task { await app.daemon.start(); await app.refreshModels() } }
            }
        default:
            EmptyView()
        }
    }

    /// Spec §5: the selected model was deleted outside Karar, so no model is selected.
    private var noModelNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(app.missingModel.map { "\($0) is no longer installed." } ?? "No model is selected.")
                    .font(.headline)
                Text("Choose a model in the toolbar, or download one.")
                    .foregroundStyle(.secondary)
            }
            Button("Download model…") { showsDownloadSheet = true }
        }
    }

    private var editor: some View {
        TextEditor(text: $app.text)
            .accessibilityIdentifier("editor")
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
                if app.model == nil {
                    noModelNote
                } else if app.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                                Text(row.answer).bold().accessibilityIdentifier("answer")
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
                if app.model == nil { noModelNote }
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
        ZStack(alignment: .trailing) {
            if let result = app.result, let tokens = result.usage?.inputTokens {
                if result.stateTruncated == true {
                    Label("Text too long for \(result.model): only the first part was read",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text("\(tokens.formatted()) tokens")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
        .monospacedDigit()
        .lineLimit(1)
        .opacity(app.isUpdating ? 0.5 : 1)
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .trailing)
        .help(tokenCounterHelp)
    }

    private var tokenCounterHelp: String {
        guard let result = app.result, let tokens = result.usage?.inputTokens else { return "" }
        return Self.tokenHelp(tokens: tokens, questions: result.answers.count)
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
