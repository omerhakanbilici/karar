import Foundation
import Observation

/// The main window's state. The `Daemon` comes from `AppDelegate`, which alone starts and stops it.
@MainActor @Observable
final class AppModel {
    typealias Decide = @MainActor (_ model: String, _ state: String, _ questions: Data) async throws -> DecideResponse
    typealias Tags = @MainActor () async throws -> [ModelInfo]

    let daemon: Daemon
    private(set) var models: [ModelInfo] = []
    var model: String? { didSet { if model != oldValue { run() } } }
    var preset = Preset.all[0] { didSet { if preset != oldValue { result = nil; run() } } }
    var text = "" { didSet { if text != oldValue { run() } } }
    private(set) var result: DecideResponse?
    private(set) var error: String?
    private(set) var isUpdating = false

    private let decide: Decide
    private let tags: Tags
    private let debounce: Duration
    private var task: Task<Void, Never>?

    init(daemon: Daemon, decide: @escaping Decide, tags: @escaping Tags, debounce: Duration = .milliseconds(300)) {
        self.daemon = daemon
        self.decide = decide
        self.tags = tags
        self.debounce = debounce
    }

    /// The current answers, in the question set's order.
    var rows: [ResultRow] {
        guard let result else { return [] }
        return preset.questionIDs.compactMap { id in result.answers[id].map { ResultRow(id: id, answer: $0) } }
    }

    /// Reloads the installed models; keeps the selection if it is still installed.
    func refreshModels() async {
        guard let fresh = try? await tags() else { return }
        models = fresh
        if !fresh.contains(where: { $0.name == model }) {
            model = fresh.first?.name
        }
    }

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
