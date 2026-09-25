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
            delete: { try await client.delete(model: $0) },
            load: { try await client.load(model: $0) }
        )
        super.init()
        #if DEBUG
        // UI checks: -KararText "…", -KararQuestions '{…}', -KararAppearance dark|light
        if let text = UserDefaults.standard.string(forKey: "KararText") { app.text = text }
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-KararQuestions"), idx + 1 < args.count {
            app.questions = Question.parse(Data(args[idx + 1].utf8))
        }
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let appearance = UserDefaults.standard.string(forKey: "KararAppearance") {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        }
        #endif
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
        .commands {
            CommandGroup(replacing: .appInfo) { AboutButton() }
        }
        Window("About Karar", id: "about") {
            AboutView(app: appDelegate.app)
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
        WindowGroup(for: AboutView.Licence.self) { $licence in
            if let licence { LicenceView(licence: licence) }
        }
        .defaultSize(width: 640, height: 520)
        .commandsRemoved()
    }
}

/// Karar ▸ About Karar opens the About window instead of the standard panel (spec §3.3).
private struct AboutButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Karar") { openWindow(id: "about") }
    }
}
