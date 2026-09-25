import SwiftUI

/// About Karar (spec §3.3): versions, links, and the licences of Karar, Ollaya and the models.
struct AboutView: View {
    let app: AppModel
    @State private var shown: Licence?

    struct Licence: Identifiable {
        let title: String
        let url: URL?
        var id: String { url?.path ?? title }
    }

    /// Catalog models grouped by licence, licences and models in catalog order.
    static var modelLicences: [(licence: String, models: [String])] {
        var groups: [(licence: String, models: [String])] = []
        for entry in CatalogEntry.all {
            if let index = groups.firstIndex(where: { $0.licence == entry.license }) {
                groups[index].models.append(entry.name)
            } else {
                groups.append((entry.license, [entry.name]))
            }
        }
        return groups
    }

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }()

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                Text("Karar").font(.title.weight(.semibold))
                Text("A Mac app for Ollaya").foregroundStyle(.secondary)
                Text("Version \(Self.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    label("Engine")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ollaya \(Daemon.bundledVersion), built in")
                        Text(running).font(.caption).foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    label("Karar")
                    licences("Apache-2.0", [
                        Licence(title: "Licence", url: Bundle.main.url(forResource: "LICENSE", withExtension: nil)),
                        Licence(title: "Notice", url: Bundle.main.url(forResource: "NOTICE", withExtension: nil)),
                    ])
                }
                GridRow {
                    label("Ollaya")
                    licences("Apache-2.0", [
                        Licence(title: "Licence", url: ollaya("LICENSE")),
                        Licence(title: "Third-party notices", url: ollaya("THIRD_PARTY_NOTICES")),
                        Licence(title: "ONNX Runtime notices", url: ollaya("onnxruntime-ThirdPartyNotices.txt")),
                    ])
                }
                GridRow {
                    label("Models")
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Self.modelLicences, id: \.licence) { group in
                            Text("\(group.licence): \(group.models.joined(separator: ", "))")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Each model has its own licence. Ollaya downloads models from their authors; Karar includes none.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 20) {
                Link("Karar on GitHub", destination: URL(string: "https://github.com/omerhakanbilici/karar")!)
                Link("ollaya.dev", destination: URL(string: "https://ollaya.dev")!)
            }
            Text("Karar is not affiliated with the Ollaya project.\n© 2026 Ömer Hakan Bilici")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 440)
        .sheet(item: $shown) { LicenceView(licence: $0) }
    }

    private var running: String {
        switch app.daemon.state {
        case .running(let owned) where !app.engineVersion.isEmpty:
            "v\(app.engineVersion) running, \(owned ? "started by Karar" : "started outside Karar")"
        case .running, .starting: "Starting…"
        case .portInUse, .failed: "Not running"
        }
    }

    private func ollaya(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Ollaya")
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private func licences(_ name: String, _ files: [Licence]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
            HStack(spacing: 12) {
                ForEach(files) { file in
                    Button(file.title) { shown = file }
                        .buttonStyle(.link)
                        .font(.caption)
                        .disabled(file.url == nil)
                }
            }
        }
    }
}

/// One licence text in a sheet. Lines are drawn lazily: the notices run to half a megabyte.
private struct LicenceView: View {
    let licence: AboutView.Licence
    private let lines: [String]
    @Environment(\.dismiss) private var dismiss

    init(licence: AboutView.Licence) {
        self.licence = licence
        let text = licence.url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Not found in the app."
        lines = text.components(separatedBy: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(licence.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { index in
                        Text(lines[index].isEmpty ? " " : lines[index])
                    }
                }
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 640, height: 520)
        .onExitCommand { dismiss() }
    }
}
