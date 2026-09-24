import SwiftUI

/// The catalog of models Karar can pull (spec §1/§3.1), opened from the sidebar's
/// "Download model…" row and the toolbar's Model menu. Reused, read-only, by onboarding (Task 6).
struct DownloadSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Download a model").font(.headline)
                Text("Models are shared with the ollaya command line.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            Divider()
            List(CatalogEntry.all) { entry in
                DownloadRow(app: app, entry: entry)
            }
            .listStyle(.plain)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 600, height: 540)
    }
}

/// One catalog row: name, summary and size on the left; installed/downloading/failed/download
/// state on the right, trailing controls vertically centred with the leading text block.
private struct DownloadRow: View {
    let app: AppModel
    let entry: CatalogEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.headline)
                    if entry.recommended { RecommendedBadge() }
                }
                Text(entry.summary).foregroundStyle(.secondary)
                Text("\(entry.languages) · \(entry.license) · ~\(formattedSize)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 8)
        // Every row's separator starts at the leading edge, not wherever the trailing column's
        // content happens to start.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
    }

    // One fixed width for every state, so the row's layout never shifts while a download's
    // caption changes length (it used to make the leading summary re-wrap mid-download).
    @ViewBuilder private var trailing: some View {
        Group {
            if app.isInstalled(entry) {
                Label("Installed", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            } else if let download = app.downloads[entry.name] {
                if let error = download.error {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                        Button("Retry") { app.download(entry) }
                    }
                } else {
                    downloading(download)
                }
            } else {
                Button("Download") { app.download(entry) }
                    .buttonStyle(.bordered)
            }
        }
        .frame(width: 180, alignment: .trailing)
    }

    private func downloading(_ download: Download) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ProgressView(value: download.fraction)
                    .frame(maxWidth: .infinity)
                Button {
                    app.cancelDownload(entry)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Cancel")
            }
            Text(compactCaption(download))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A one-line, near-constant-length stand-in for `DownloadCaption` in the sheet row: the
    /// full per-part caption's changing byte counts made the row jump while a download ran.
    private func compactCaption(_ download: Download) -> String {
        let allDone = download.parts.allSatisfy { $0.total > 0 && $0.completed >= $0.total }
        if allDone && !download.isFinished { return "Verifying…" }
        guard let speed = download.bytesPerSecond, speed > 0 else { return "Waiting…" }
        let percent = Int(download.fraction * 100)
        let remaining = download.parts.reduce(Int64(0)) { $0 + max($1.total - $1.completed, 0) }
        let eta = Duration.seconds((Double(remaining) / speed).rounded())
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
        return "\(percent)% · \(eta) left"
    }
}

/// The "Recommended" tag next to a catalog entry's name; reused by onboarding (Task 6).
struct RecommendedBadge: View {
    var body: some View {
        Text("Recommended")
            .font(.caption2)
            .foregroundStyle(.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: .capsule)
    }
}

/// One download part's progress line, e.g. "420 MB of 854 MB · 40 MB/s · 12 sec left". Reused by
/// onboarding (Task 6).
struct DownloadCaption: View {
    let download: Download
    let part: Download.Part

    var body: some View {
        Text(text).font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
    }

    private var text: String {
        let bytes = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        if part.isDone { return "\(bytes(part.total)) · Done" }
        if part.completed == 0 && download.bytesPerSecond == nil { return "Waiting…" }
        var pieces = ["\(bytes(part.completed)) of \(bytes(part.total))"]
        if let speed = download.bytesPerSecond { pieces.append("\(bytes(Int64(speed)))/s") }
        if let left = download.secondsLeft(part) {
            pieces.append(Duration.seconds(left.rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)) + " left")
        }
        return pieces.joined(separator: " · ")
    }
}
