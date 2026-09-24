import SwiftUI

/// Owns the engine's lifecycle at the app level, not the window: it must survive window
/// close/reopen and stop exactly once on quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app: AppModel

    override init() {
        let client = OllayaClient.local
        app = AppModel(
            daemon: Daemon(probe: { await client.liveness() }, launch: Daemon.bundledLaunch),
            decide: { try await client.decide(model: $0, state: $1, questions: $2) },
            tags: { try await client.tags() },
            version: { try await client.version() },
            pull: { client.pull(model: $0) },
            delete: { try await client.delete(model: $0) }
        )
        super.init()
        #if DEBUG
        // UI checks without typing (no Accessibility): `-KararText "…"`, `-KararQuestions '{…}'`.
        if let text = UserDefaults.standard.string(forKey: "KararText") { app.text = text }
        if let json = UserDefaults.standard.string(forKey: "KararQuestions") { app.questions = Question.parse(Data(json.utf8)) }
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests are hosted in the app; don't start a real engine under them.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task { await app.daemon.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        app.daemon.stop()
    }
}

@main
struct KararApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Karar", id: "main") {
            RootView(app: appDelegate.app)
        }
    }
}
