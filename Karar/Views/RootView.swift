import SwiftUI

/// The window's root. The only place that starts the engine connection: it never starts the
/// daemon itself (`AppDelegate` alone does that), it just reacts once the daemon is `.running`
/// and refreshes the model list whenever the app comes back to the front.
struct RootView: View {
    let app: AppModel

    var body: some View {
        Group {
            // A daemon that failed or found the port taken needs MainView's banner even
            // mid-onboarding, so it is checked first.
            if !app.daemon.state.isRunning, app.daemon.state != .starting {
                MainView(app: app)
            } else if app.isOnboarding {
                OnboardingView(app: app)
            } else if showsStartupProgress {
                ProgressView("Starting Ollaya…")
                    .frame(minWidth: 720, minHeight: 480)
            } else {
                MainView(app: app)
            }
        }
        .task(id: app.daemon.state) {
            guard case .running = app.daemon.state else { return }
            await app.connect()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await app.refreshModels() }
        }
    }

    /// Until models have loaded once, a full-window spinner stands in for `MainView`. (A failed
    /// daemon never reaches here: the `.failed` case above already routed to `MainView`.)
    private var showsStartupProgress: Bool { !app.modelsLoaded }
}
