import SwiftUI

@main
struct KararApp: App {
    @State private var daemon: Daemon

    init() {
        _daemon = State(initialValue: Daemon(
            probe: { await OllayaClient.local.liveness() },
            launch: Daemon.bundledLaunch
        ))
    }

    var body: some Scene {
        WindowGroup {
            StatusView(daemon: daemon)
                .task {
                    // Unit tests are hosted in the app; don't start a real engine under them.
                    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                    await daemon.start()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    daemon.stop()
                }
        }
    }
}
