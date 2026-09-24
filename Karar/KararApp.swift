import SwiftUI

/// Owns the engine's lifecycle at the app level, not the window: it must survive window
/// close/reopen and stop exactly once on quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let daemon: Daemon

    override init() {
        daemon = Daemon(
            probe: { await OllayaClient.local.liveness() },
            launch: Daemon.bundledLaunch
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests are hosted in the app; don't start a real engine under them.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task { await daemon.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        daemon.stop()
    }
}

@main
struct KararApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Karar", id: "main") {
            StatusView(daemon: appDelegate.daemon)
        }
    }
}
