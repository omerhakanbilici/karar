import SwiftUI

/// One question in advanced mode (spec §3.2): id, type, instructions and options, all editable,
/// with the raw answer. A validation error from the engine marks the card in system red (spec §5).
///
/// Every text field below that fills the remaining row width (instructions, and each option's
/// second field) carries an explicit `minWidth`. Without it, `.inspector` (Task 6) renegotiates the
/// detail column's width against a field that reports back "however much you give me": the window
/// server never settles and macOS aborts with "too many Update Constraints in Window passes"
/// (confirmed by bisection: the crash needs both an open inspector and an unconstrained-width field
/// in the cards; either alone is fine). The label-only fields (`id`, a choice label, a score index)
/// already have a fixed width and never triggered it.
struct QuestionCard: View {
    @Binding var question: Question
    let answer: Answer?
    let error: String?
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("id", text: $question.key)
                    .font(.body.monospaced())
                    .frame(maxWidth: 220)
                Picker("Type", selection: Binding(get: { question.kind }, set: { question.change(to: $0) })) {
                    ForEach(Question.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 12)
                if let answer {
                    Text(answer.rawText)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button(action: remove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this question")
            }
            TextField("Instructions (when empty, the model reads the id)", text: $question.instructions, axis: .vertical)
                .lineLimit(1...4)
                .frame(minWidth: 120)
            options
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(12)
        .background(.quinary, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(error == nil ? AnyShapeStyle(.separator) : AnyShapeStyle(.red), lineWidth: error == nil ? 1 : 2)
        }
    }

    @ViewBuilder private var options: some View {
        switch question.kind {
        case .choice:
            ForEach($question.options) { $option in
                HStack(spacing: 8) {
                    TextField("label", text: $option.label)
                        .font(.body.monospaced())
                        .frame(width: 160)
                    TextField("Description (optional)", text: $option.text)
                        .frame(minWidth: 120)
                    removeButton(option)
                }
            }
            addButton("Add option") { question.options.append(.init(label: Self.freeLabel(in: question.options))) }
        case .score:
            ForEach($question.options) { $level in
                let index = question.options.firstIndex { $0.id == level.id } ?? 0
                HStack(spacing: 8) {
                    Text(verbatim: "\(index)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    TextField("Level \(index)", text: $level.text)
                        .frame(minWidth: 120)
                    removeButton(level)
                }
            }
            addButton("Add level") { question.options.append(.init()) }
        case .noul:
            ForEach($question.options) { $option in
                HStack(spacing: 8) {
                    Text(option.label == "true" ? "True" : "False")
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .leading)
                    TextField(option.label == "true" ? "When the statement holds (optional)" : "When it does not (optional)",
                              text: $option.text)
                        .frame(minWidth: 120)
                }
            }
        }
    }

    /// The first `option_<n>` (n from count+1 upward) not already used, so removing an earlier
    /// option and adding a new one never recreates a label already in use (choice criteria are a
    /// JSON object keyed by label: a repeat would silently collide with an existing key).
    private static func freeLabel(in options: [Question.Option]) -> String {
        var n = options.count + 1
        while options.contains(where: { $0.label == "option_\(n)" }) { n += 1 }
        return "option_\(n)"
    }

    private func removeButton(_ option: Question.Option) -> some View {
        Button {
            question.options.removeAll { $0.id == option.id }
        } label: {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Remove")
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}
