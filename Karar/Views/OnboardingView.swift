import SwiftUI

/// First run, or no model installed (spec §3.1): welcome → choose a first model → download → get
/// started. Shown by `RootView` while `app.isOnboarding`.
struct OnboardingView: View {
    let app: AppModel

    enum Step: Hashable { case welcome, choose, downloading(CatalogEntry) }

    @State private var step: Step
    @State private var choice: CatalogEntry

    init(app: AppModel) {
        self.app = app
        // A download already under way (or failed) picks up at its progress screen.
        let started = CatalogEntry.all.first { app.downloads[$0.name] != nil }
        _step = State(initialValue: started.map { .downloading($0) } ?? .welcome)
        _choice = State(initialValue: started ?? CatalogEntry.all.first(where: \.recommended) ?? CatalogEntry.all[0])
    }

    var body: some View {
        Group {
            switch step {
            case .welcome: welcome
            case .choose: choose
            case .downloading(let entry): downloading(entry)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    // MARK: Steps

    private var welcome: some View {
        page(alignment: .center) {
            VStack(spacing: 24) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                VStack(spacing: 8) {
                    Text("Welcome to Karar").font(.largeTitle.weight(.semibold))
                    Text("Ask typed questions about any text and get calibrated answers in milliseconds. Everything runs on this Mac.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Label {
                    Text(app.engineVersion.isEmpty ? "Ollaya engine ready" : "Ollaya engine ready · v\(app.engineVersion)")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                }
            }
        } buttons: {
            Button("Continue") { step = .choose }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var choose: some View {
        page(alignment: .top) {
            VStack(alignment: .leading, spacing: 16) {
                header("Choose your first model", subtitle: "You can download more models later.")
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(CatalogEntry.all) { entry in
                            if entry != CatalogEntry.all.first { Divider() }
                            ChoiceRow(entry: entry, isSelected: entry == choice)
                                .onTapGesture { choice = entry }
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(.rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            }
        } buttons: {
            Button("Back") { step = .welcome }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
            Button("Download") {
                app.download(choice)
                step = .downloading(choice)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func downloading(_ entry: CatalogEntry) -> some View {
        // Until the model's first line lands (and just after Cancel), show the empty bars.
        let download = app.downloads[entry.name] ?? Download(for: entry)
        return page(alignment: .top) {
            VStack(alignment: .leading, spacing: 24) {
                header("Downloading \(entry.name)", subtitle: entry.summary)
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(download.parts) { part in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(part.name).font(.headline).lineLimit(1)
                            ProgressView(value: part.fraction)
                            DownloadCaption(download: download, part: part)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let error = download.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
        } buttons: {
            if download.error != nil {
                Button("Back") {
                    app.cancelDownload(entry)
                    step = .choose
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                Button("Retry") { app.download(entry) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") {
                    app.cancelDownload(entry)
                    step = .choose
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                .disabled(download.isFinished)
                // Only once the post-pull refresh lists the model, so the main window opens on it.
                Button("Get started") { app.getStarted(with: entry) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!(download.isFinished && app.isInstalled(entry)))
            }
        }
    }

    // MARK: Layout

    /// One step: content in a centred column, buttons in a bottom bar aligned trailing.
    private func page(alignment: Alignment, @ViewBuilder content: () -> some View,
                      @ViewBuilder buttons: () -> some View) -> some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: 480, maxHeight: .infinity, alignment: alignment)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 32)
            HStack(spacing: 12) {
                Spacer()
                buttons()
            }
            .padding(20)
        }
    }

    private func header(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

/// One radio row in "Choose your first model"; the whole row is the hit target.
private struct ChoiceRow: View {
    let entry: CatalogEntry
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.headline)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.headline)
                    if entry.recommended { RecommendedBadge() }
                }
                Text(entry.summary).foregroundStyle(.secondary)
                Text("\(entry.languages) · \(entry.license) · ~\(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
