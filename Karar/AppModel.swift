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

    let daemon: Daemon
    private(set) var models: [ModelInfo] = []
    var model: String? { didSet { if model != oldValue { run() } } }
    var preset = Preset.all[0] { didSet { if preset != oldValue { result = nil; run() } } }
    var text = "" { didSet { if text != oldValue { run() } } }
    private(set) var result: DecideResponse?
    private(set) var error: String?
    private(set) var isUpdating = false

    private(set) var modelsLoaded = false
    private(set) var engineVersion = ""
    private(set) var isOnboarding = false
    private(set) var downloads: [String: Download] = [:]
    var deleteError: String?

    private let decide: Decide
    private let tags: Tags
    private let version: Version
    private let pull: Pull
    private let deleteModel: Delete
    private let debounce: Duration
    private var task: Task<Void, Never>?
    private var refreshes = 0
    private var pullTasks: [String: Task<Void, Never>] = [:]

    init(daemon: Daemon, decide: @escaping Decide, tags: @escaping Tags, version: @escaping Version,
         pull: @escaping Pull, delete: @escaping Delete, debounce: Duration = .milliseconds(300)) {
        self.daemon = daemon
        self.decide = decide
        self.tags = tags
        self.version = version
        self.pull = pull
        self.deleteModel = delete
        self.debounce = debounce
    }

    /// The current answers, in the question set's order.
    var rows: [ResultRow] {
        guard let result else { return [] }
        return preset.questionIDs.compactMap { id in result.answers[id].map { ResultRow(id: id, answer: $0) } }
    }

    /// Called when the engine is ready.
    func connect() async {
        await refreshModels()
        engineVersion = (try? await version()) ?? ""
    }

    /// Reloads the installed models; keeps the selection if it is still installed. When calls
    /// overlap, the newest one wins. Finding no model starts onboarding (spec §3.1).
    func refreshModels() async {
        refreshes += 1
        let call = refreshes
        guard let fresh = try? await tags(), call == refreshes else { return }
        models = fresh
        modelsLoaded = true
        if fresh.isEmpty { isOnboarding = true }
        if !fresh.contains(where: { $0.name == model }) {
            model = fresh.first?.name
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
                downloads[name]?.error = error.localizedDescription
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

    func delete(_ model: String) async {
        do {
            try await deleteModel(model)
        } catch {
            deleteError = error.localizedDescription
        }
        await refreshModels()
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

    /// Live results (spec §3.2): cancel the request in flight, wait for typing to pause, ask again.
    private func run() {
        task?.cancel()
        guard let model, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            task = nil
            isUpdating = false
            result = nil
            error = nil
            return
        }
        let text = text, questions = preset.questions
        isUpdating = true
        task = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            do {
                let response = try await decide(model, text, questions)
                guard !Task.isCancelled else { return }
                result = response
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                result = nil
                self.error = error.localizedDescription
            }
            isUpdating = false
        }
    }
}
