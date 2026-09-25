import SwiftUI

/// About Karar (spec §3.3): versions, links, and the licences of Karar, Ollaya and the models.
struct AboutView: View {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow

    struct Licence: Identifiable, Codable, Hashable {
        /// "Karar" or "Ollaya": disambiguates windows that would otherwise share a title (both a
        /// Karar and an Ollaya licence are titled "Licence"), and survives a bundle move (DMG →
        /// /Applications, translocation) unlike a stored absolute URL.
        let owner: String
        let title: String
        let name: String
        let subdirectory: String?
        var id: String { (subdirectory ?? "") + "/" + name }
        var url: URL? { Bundle.main.url(forResource: name, withExtension: nil, subdirectory: subdirectory) }
        var windowTitle: String { "\(owner) \(title)" }
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
                        Licence(owner: "Karar", title: "Licence", name: "LICENSE", subdirectory: nil),
                        Licence(owner: "Karar", title: "Notice", name: "NOTICE", subdirectory: nil),
                    ])
                }
                GridRow {
                    label("Ollaya")
                    licences("Apache-2.0", [
                        Licence(owner: "Ollaya", title: "Licence", name: "LICENSE", subdirectory: "Ollaya"),
                        Licence(owner: "Ollaya", title: "Third-party notices", name: "THIRD_PARTY_NOTICES", subdirectory: "Ollaya"),
                        Licence(owner: "Ollaya", title: "ONNX Runtime notices", name: "onnxruntime-ThirdPartyNotices.txt", subdirectory: "Ollaya"),
                    ])
                }
                GridRow {
                    label("Models")
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Self.modelLicences, id: \.licence) { group in
                            Text("\(group.licence): \(group.models.joined(separator: ", "))")
                        }
                        Text("Each model has its own licence. Ollaya downloads models from their authors; Karar includes none.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private var running: String {
        switch app.daemon.state {
        case .running(let owned) where !app.engineVersion.isEmpty:
            "v\(app.engineVersion) running, \(owned ? "started by Karar" : "started outside Karar")"
        case .running, .starting: "Starting…"
        case .portInUse, .failed: "Not running"
        }
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
                    Button(file.title) { openWindow(value: file) }
                        .buttonStyle(.link)
                        .font(.caption)
                        .disabled(file.url == nil)
                }
            }
        }
    }
}

/// One licence text in its own window (like macOS "Acknowledgements" windows). Lines are drawn
/// lazily: the notices run to half a megabyte.
struct LicenceView: View {
    let licence: AboutView.Licence
    private let lines: [String]

    init(licence: AboutView.Licence) {
        self.licence = licence
        let text = licence.url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Not found in the app."
        lines = text.components(separatedBy: "\n")
    }

    var body: some View {
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
        .frame(minWidth: 480, minHeight: 320)
        .navigationTitle(licence.windowTitle)
    }
}
