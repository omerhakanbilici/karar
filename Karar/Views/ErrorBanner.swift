import SwiftUI

/// A problem with the engine, across the top of the window (spec §5): what happened, what to do,
/// and the buttons that do it. System colours only (spec §4).
struct ErrorBanner<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .help(message)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) { actions }
                .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}
