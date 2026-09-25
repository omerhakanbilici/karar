import Foundation
import Observation

/// The main window's state. The `Daemon` comes from `AppDelegate`, which alone starts and stops it.
@MainActor @Observable
final class AppModel {
    typealias Decide = @MainActor (_ model: String, _ state: String, _ questions: Data) async throws -> DecideResponse
    typealias Tags = @MainActor () async throws -> [ModelInfo]
    typealias Version = @MainActor () async throws -> String
    typealias Pull = @MainActor (_ model: String) -> AsyncThrowingStream<PullProgress, Error>
    typealias Delete = @MainActor (_ model: String) async throws -> Void
    typealias Load = @MainActor (_ model: String) async throws -> Void

    let daemon: Daemon
    private(set) var models: [ModelInfo] = []
    var model: String? {
        didSet {
            guard model != oldValue else { return }
            if model != nil { missingModel = nil }
            preload()
            run()
        }
    }
    /// The question set in use when `isCustom` is false. Choosing a preset (even the one on screen)
    /// leaves "My questions", which stay in memory for `useMyQuestions()`.
    var preset = Preset.all[0] { didSet { if preset != oldValue || isCustom { usePreset() } } }
    var text = "" { didSet { if text != oldValue { run() } } }
    /// The questions in use, in order: the preset's, or "My questions" once any is edited (spec §3.2).
    var questions: [Question] {
        get { currentQuestions }
        set {
            guard newValue != currentQuestions else { return }
            currentQuestions = newValue
            isCustom = true
            run()
        }
    }
    private(set) var isCustom = false
    /// Validation messages by question id: from a 422's `detail[].loc` (spec §5), or a duplicate id.
    private(set) var questionErrors: [String: String] = [:]
    private(set) var pins: [Pin] = []
    private(set) var result: DecideResponse?
    private(set) var error: String?
    private(set) var isUpdating = false

    private(set) var modelsLoaded = false
    /// Why the last `/api/tags` failed, shown in the window's banner (spec §5); nil once it works.
    private(set) var modelsError: String?
    /// The selected model after it disappeared outside Karar (spec §5); cleared once one is picked.
    private(set) var missingModel: String?
    private(set) var engineVersion = ""
    private(set) var isOnboarding = false
    private(set) var downloads: [String: Download] = [:]
    var deleteError: String?

    private let decide: Decide
    private let tags: Tags
    private let version: Version
    private let pull: Pull
    private let deleteModel: Delete
    private let load: Load
    private let debounce: Duration
    private var task: Task<Void, Never>?
    private var currentQuestions = Question.parse(Preset.all[0].questions)
    private var myQuestions: [Question]?   // kept while a preset is in use
    private var refreshes = 0   // refreshModels() calls started
    private var applied = 0     // the newest call whose answer is on screen
    private var pullTasks: [String: Task<Void, Never>] = [:]

    init(daemon: Daemon, decide: @escaping Decide, tags: @escaping Tags, version: @escaping Version,
         pull: @escaping Pull, delete: @escaping Delete, load: @escaping Load = { _ in }, debounce: Duration = .milliseconds(300)) {
        self.daemon = daemon
        self.decide = decide
        self.tags = tags
        self.version = version
        self.pull = pull
        self.deleteModel = delete
        self.load = load
        self.debounce = debounce
    }

    /// The current answers, in the questions' order.
    var rows: [ResultRow] {
        guard let result else { return [] }
        return currentQuestions.compactMap { q in result.answers[q.key].map { ResultRow(id: q.key, answer: $0) } }
    }

    /// The `/api/decide` body for the current input, for "Copy as curl".
    var requestBody: Data? {
        guard let model, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try? OllayaClient.decideBody(model: model, state: text, questions: questionsJSON)
    }

    /// A preset is sent byte for byte; "My questions" are written in card order.
    private var questionsJSON: Data {
        isCustom ? Question.json(currentQuestions) : preset.questions
    }

    /// "My questions…" (spec §3.2): the set kept from before, or else a copy of the questions on screen.
    func useMyQuestions() {
        guard !isCustom else { return }
        if let myQuestions { currentQuestions = myQuestions }
        isCustom = true
        result = nil
        run()
    }

    func addQuestion() {
        var n = questions.count + 1
        while questions.contains(where: { $0.key == "question_\(n)" }) { n += 1 }
        questions.append(Question(key: "question_\(n)", kind: .noul))
    }

    private func usePreset() {
        if isCustom { myQuestions = currentQuestions }
        isCustom = false
        currentQuestions = Question.parse(preset.questions)
        result = nil
        run()
    }

    /// ⌘↩ (spec §3.2): keeps the input and its answers in the sidebar for this session.
    func pin() {
        guard let model, result != nil, !isUpdating else { return }
        pins.insert(Pin(text: text, model: model, setName: isCustom ? "My questions" : preset.name,
                        preset: preset, questions: isCustom ? currentQuestions : nil, rows: rows), at: 0)
    }

    /// Brings back a pin's model (if still installed), question set and text; the answers run again.
    func restore(_ pin: Pin) {
        if models.contains(where: { $0.name == pin.model }) { model = pin.model }
        if let questions = pin.questions {
            currentQuestions = questions
            isCustom = true
        } else {
            preset = pin.preset
        }
        text = pin.text
        result = nil
        questionErrors = [:]
        run()
    }

    func unpin(_ pin: Pin) {
        pins.removeAll { $0.id == pin.id }
    }

    /// Called whenever the engine becomes ready: at launch and after every (re)start. Re-running
    /// replaces an error left from before an automatic restart (spec §5); skipped when the refresh
    /// already changed the selection, since that ran through `model`'s `didSet` already, which also
    /// preloaded it.
    func connect() async {
        let before = model
        await refreshModels()
        engineVersion = (try? await version()) ?? ""
        if model == before {
            preload()
            run()
        }
    }

    /// Reloads the installed models. The newest call's answer wins; an older one that answers later
    /// is dropped. A failure keeps the list and shows why (spec §5).
    ///
    /// The selection stays while installed. One that disappeared outside Karar is cleared, not
    /// replaced (spec §5), and comes back if the model does. Finding no model starts onboarding
    /// (spec §3.1); finding some ends it, unless one of Karar's own downloads is running or done
    /// (its "Get started" is then the way out).
    func refreshModels() async {
        refreshes += 1
        let call = refreshes
        let fresh: [ModelInfo]
        do {
            fresh = try await tags()
        } catch {
            guard call > applied else { return }
            applied = call
            modelsError = error.localizedDescription
            return
        }
        guard call > applied else { return }
        applied = call
        modelsError = nil
        models = fresh
        modelsLoaded = true
        if fresh.isEmpty {
            isOnboarding = true
        } else if isOnboarding, !downloads.values.contains(where: { $0.error == nil }) {
            isOnboarding = false
        }
        if let model, !fresh.contains(where: { $0.name == model }) {
            missingModel = model
            self.model = nil
        } else if model == nil {
            if let missingModel {
                if fresh.contains(where: { $0.name == missingModel }) { model = missingModel }
            } else {
                model = fresh.first?.name
            }
        }
    }

    func isInstalled(_ entry: CatalogEntry) -> Bool {
        models.contains { $0.name == entry.canonicalName }
    }

    /// Starts a pull, or retries a failed one; the daemon resumes from what it already has.
    func download(_ entry: CatalogEntry) {
        let name = entry.name
        guard pullTasks[name] == nil else { return }
        downloads[name] = Download(for: entry)
        let stream = pull(name)
        pullTasks[name] = Task {
            do {
                for try await progress in stream {
                    downloads[name]?.apply(progress, at: .now)
                }
            } catch {
                downloads[name]?.error = Self.pullMessage(error)
            }
            pullTasks[name] = nil
            if Task.isCancelled {
                downloads[name] = nil
            } else if downloads[name]?.error == nil {
                await refreshModels()
            }
        }
    }

    /// Closing the stream detaches Karar from the pull; the daemon stops it and keeps the partial
    /// blobs (docs/api.md §10). The task above then forgets the download. A download that has
    /// already ended (failed or finished) has no task left to cancel, so drop its entry directly.
    func cancelDownload(_ entry: CatalogEntry) {
        if let task = pullTasks[entry.name] {
            task.cancel()
        } else {
            downloads[entry.name] = nil
        }
    }

    /// A failed pull's text on its row (spec §5), by error code (docs/api.md §4.2, §7.6).
    static func pullMessage(_ error: Error) -> String {
        if error is URLError { return "Lost the connection to Ollaya." }
        guard let error = error as? OllayaError else { return error.localizedDescription }
        switch error.code {
        case "REGISTRY_ERROR": return "Could not reach the model registry. Check your internet connection."
        case "DIGEST_MISMATCH": return "A downloaded file was damaged and has been discarded."
        case "STORAGE_ERROR": return "Could not save the model: \(error.error)"
        case "MODEL_NOT_FOUND": return "This model is not in the registry."
        default: return error.error
        }
    }

    func delete(_ name: String) async {
        do {
            try await deleteModel(name)
            if model == name { model = nil }   // deleted here: the first model left takes over
        } catch {
            deleteError = error.localizedDescription
        }
        await refreshModels()
        // A finished download of the just-deleted model is now stale; drop it so onboarding (or
        // the download sheet) doesn't resume at a download that can never be cancelled or finished.
        downloads = downloads.filter { !$0.value.isFinished }
    }

    /// Leaves onboarding with a result on screen at once (spec §3.1).
    func getStarted(with entry: CatalogEntry) {
        isOnboarding = false
        model = entry.canonicalName
        preset = Preset.all.first { $0.id == "triage" } ?? Preset.all[0]
        text = Self.sampleTicket
    }

    static let sampleTicket = """
        Hi, I was charged twice for my subscription this month. Please refund the second payment. \
        I have been a customer for three years, but if this is not fixed by Friday I will cancel my account.
        """

    /// Loads the selected model in the background (docs/api.md §7.3), so the first answer after
    /// picking it, or after an engine restart, doesn't wait 2.5–3.3 s for the load. Best effort.
    private func preload() {
        guard let model else { return }
        Task { try? await load(model) }
    }

    /// Live results (spec §3.2): cancel the request in flight, wait for typing to pause, ask again.
    private func run() {
        task?.cancel()
        let duplicates = Question.duplicateKeys(currentQuestions)
        guard let model, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, duplicates.isEmpty else {
            task = nil
            isUpdating = false
            result = nil
            error = nil
            questionErrors = Dictionary(uniqueKeysWithValues: duplicates.map { ($0, "Another question has the same id.") })
            return
        }
        let text = text, questions = questionsJSON
        isUpdating = true
        task = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            do {
                let response = try await decide(model, text, questions)
                guard !Task.isCancelled else { return }
                result = response
                error = nil
                questionErrors = [:]
                isUpdating = false
            } catch {
                guard !Task.isCancelled else { return }
                result = nil
                isUpdating = false
                if (error as? OllayaError)?.code == "MODEL_NOT_FOUND" {
                    // Deleted outside Karar (spec §5): the refresh clears the selection, and the
                    // missing-model note replaces this message.
                    self.error = nil
                    await refreshModels()
                } else {
                    show(error)
                }
            }
        }
    }

    /// A 422's issues go to the question their `loc` names (spec §5); the rest, or any other error,
    /// is shown above the answers.
    private func show(_ error: Error) {
        let issues = (error as? OllayaError)?.detail ?? []
        var byQuestion: [String: String] = [:]
        for issue in issues {
            guard let id = issue.questionID else { continue }
            byQuestion[id] = byQuestion[id].map { $0 + "\n" + issue.msg } ?? issue.msg
        }
        questionErrors = byQuestion
        let other = issues.filter { $0.questionID == nil }.map(\.msg)
        self.error = issues.isEmpty ? error.localizedDescription : other.isEmpty ? nil : other.joined(separator: "\n")
    }
}

/// A pinned input and its answers (spec §3.2; in memory only, v1).
struct Pin: Identifiable {
    let id = UUID()
    let text: String
    let model: String            // the model picked, e.g. `laya:latest`
    let setName: String          // "Support ticket", "My questions"
    let preset: Preset
    let questions: [Question]?   // "My questions" at the time; nil for a preset
    let rows: [ResultRow]

    /// The text's first line, for the sidebar.
    var title: String {
        text.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }
}
