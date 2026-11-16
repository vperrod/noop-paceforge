import SwiftUI
import StrandDesign

/// One journal question as drawn in 5b and 5d: its wording, an optional line under it, and Yes and No. A yes to a count asks how many
/// (and the time of the last one), a yes to a 1 to 5 question asks for the number, a yes to a time question asks for the time.
struct PFJournalQuestionRow530: View {
    typealias Logic = PFJournalLogic530

    let question: PFJournalDoc530.Question
    let answer: Logic.Answer?
    let onChoose: (Bool) -> Void
    let onNumber: (Double?) -> Void
    let onNote: (String?) -> Void

    private var key: String { question.key ?? "" }
    private var kind: String { Logic.kind(question) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Logic.prompt(question))
                        .font(LookFont.text(15, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint = question.hint, !hint.isEmpty {
                        Text(hint)
                            .font(LookFont.text(12.5))
                            .foregroundStyle(NoopLook.textTertiary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                choice(question.yes ?? "Yes", yes: true)
                choice(question.no ?? "No", yes: false)
            }
            if answer?.yes == true { followUp }
        }
        .padding(.vertical, 9)
        .containerIdentifier("pf530-journal-row-\(key)")
    }

    // MARK: Yes and No

    private func choice(_ title: String, yes: Bool) -> some View {
        let isOn = answer?.yes == yes
        return Button { onChoose(yes) } label: {
            Text(title)
                .lookCaps(11, weight: .semibold)
                .foregroundStyle(isOn ? Color.black.opacity(0.85) : NoopLook.textPrimary)
                .padding(.horizontal, 12)
                .frame(minWidth: 54, minHeight: 40)
                .background(Capsule().fill(isOn ? (yes ? StrandPalette.accent : Color.white) : NoopLook.row))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(Logic.prompt(question))")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("pf530-journal-\(yes ? "yes" : "no")-\(key)")
    }

    // MARK: After a yes

    @ViewBuilder private var followUp: some View {
        switch kind {
        case "count": countControls
        case "scale": scaleControls
        case "time": timeControl
        default: EmptyView()
        }
    }

    private var countControls: some View {
        let count = Int(answer?.number ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("How many")
                    .font(LookFont.text(13.5, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                stepper("minus", label: "Fewer", id: "minus", isDisabled: count <= 1) { onNumber(Double(count - 1)) }
                Text("\(count)")
                    .font(LookFont.numeral(20))
                    .foregroundStyle(NoopLook.textPrimary)
                    .frame(minWidth: 28)
                    .accessibilityIdentifier("pf530-journal-count-\(key)")
                stepper("plus", label: "More", id: "plus", isDisabled: count >= 30) { onNumber(Double(count + 1)) }
            }
            lastOne
        }
    }

    private func stepper(_ symbol: String, label: String, id: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "\(symbol).circle")
                .font(.system(size: 24))
                .foregroundStyle(isDisabled ? NoopLook.textMuted : NoopLook.textSecondary)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("\(label), \(Logic.prompt(question))")
        .accessibilityIdentifier("pf530-journal-count-\(id)-\(key)")
    }

    /// The time of the last one, kept as the answer's note.
    @ViewBuilder private var lastOne: some View {
        if let minutes = Logic.minutes(ofNote: answer?.note) {
            HStack(spacing: 10) {
                Text("Time of the last one")
                    .font(LookFont.text(13.5, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                DatePicker("Time of the last one", selection: timeBinding(minutes) { onNote(Logic.note(lastAt: $0)) },
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Button { onNote(nil) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(NoopLook.textTertiary).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove the time")
            }
        } else {
            Button { onNote(Logic.note(lastAt: PFJournalSession530.minutesNow())) } label: {
                Text("Add the time of the last one")
                    .font(LookFont.text(13.5, weight: .semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(minHeight: 36, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pf530-journal-last-\(key)")
        }
    }

    private var scaleControls: some View {
        HStack(spacing: 8) {
            Text("How much")
                .font(LookFont.text(13.5, weight: .medium))
                .foregroundStyle(NoopLook.textSecondary)
            Spacer(minLength: 8)
            ForEach(1...5, id: \.self) { value in
                let isOn = answer?.number == Double(value)
                Button { onNumber(Double(value)) } label: {
                    Text("\(value)")
                        .font(LookFont.numeral(16))
                        .foregroundStyle(isOn ? Color.black.opacity(0.85) : NoopLook.textPrimary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(isOn ? StrandPalette.accent : NoopLook.row))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                .accessibilityLabel("\(value) of 5, \(Logic.prompt(question))")
                .accessibilityIdentifier("pf530-journal-scale-\(value)-\(key)")
            }
        }
    }

    private var timeControl: some View {
        HStack(spacing: 10) {
            Text("At")
                .font(LookFont.text(13.5, weight: .medium))
                .foregroundStyle(NoopLook.textSecondary)
            Spacer(minLength: 8)
            DatePicker("Time", selection: timeBinding(answer?.number ?? PFJournalSession530.minutesNow()) { onNumber($0) },
                       displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }

    /// A time of day in minutes after midnight, as the date a time picker edits.
    private func timeBinding(_ minutes: Double, set: @escaping (Double) -> Void) -> Binding<Date> {
        Binding(
            get: {
                let whole = Int(minutes)
                return Calendar.current.date(bySettingHour: (whole / 60) % 24, minute: whole % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                set(Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)))
            })
    }
}
