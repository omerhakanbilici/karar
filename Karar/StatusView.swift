import SwiftUI

/// Phase 1 window: engine status and installed models.
struct StatusView: View {
    let daemon: Daemon
    @State private var version = ""
    @State private var models: [ModelInfo] = []

    var body: some View {
        Group {
            switch daemon.state {
            case .starting:
                ProgressView("Starting Ollaya…")
            case .running(let owned):
                List {
                    Section {
                        LabeledContent("Engine", value: "Ollaya \(version)")
                        LabeledContent("Mode", value: owned ? "Started by Karar" : "Already running")
                    }
                    Section("Installed models") {
                        if models.isEmpty {
                            Text("No models yet. Run `ollaya pull laya` in Terminal.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(models, id: \.name) { model in
                            LabeledContent(model.name, value: model.details.parameterSize)
                        }
                    }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Ollaya is not running", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await daemon.start() } }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .task(id: daemon.state) {
            guard case .running = daemon.state else { return }
            version = (try? await OllayaClient.local.version()) ?? ""
            models = (try? await OllayaClient.local.tags()) ?? []
        }
    }
}
