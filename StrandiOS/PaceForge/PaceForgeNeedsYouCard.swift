import SwiftUI
import StrandDesign

/// The Needs you card at the top of PaceForge Today. It exists only while PaceForge is waiting on something; the answered
/// item leaves at once and comes back with a reason if the server did not take it (see `PFModel.submitAnswer`).
struct PFNeedsYouCard: View {
    let items: [PFNeedsItem]

    @EnvironmentObject private var model: PFModel

    var body: some View {
        PFCard(title: "Needs you", icon: "bell.badge", trailing: {
            PFChip(text: "\(items.count)", color: PFNeutral.other)
                .accessibilityIdentifier("pf-needs-count")
        }) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(StrandPalette.hairline) }
                    VStack(alignment: .leading, spacing: 8) {
                        row(item)
                        if let note = model.needsNotes[item.id] {
                            Label(note, systemImage: "exclamationmark.circle")
                                .font(StrandFont.caption.weight(.semibold))
                                .foregroundStyle(PFColor.warning)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("pf-needs-error-\(item.id)")
                        }
                    }
                }
            }
        }
        .containerIdentifier("pf-needs-card")
    }

    @ViewBuilder private func row(_ item: PFNeedsItem) -> some View {
        switch item.kind {
        case .treadmillPace: PFNeedsTreadmillRow(item: item)
        case .proposal: PFNeedsProposalRow(item: item)
        case .rpe: PFNeedsScaleRow(item: item, values: Array(1...10), columns: 5, prefix: "rpe")
        case .feel: PFNeedsScaleRow(item: item, values: Array(1...5), columns: 5, prefix: "feel")
        }
    }
}

/// Sends an answer without blocking the tap: the model does the work.
private func send(_ model: PFModel, _ answer: PFNeedsAnswer, for item: PFNeedsItem) {
    Task { @MainActor in await model.submitAnswer(answer, for: item) }
}

private struct PFNeedsHeader: View {
    let item: PFNeedsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let meaning = item.meaning {
                Text(meaning)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PFNeedsButton: View {
    let title: String
    var prominent = false
    var isEnabled = true
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(StrandFont.subhead.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
        .tint(prominent ? StrandPalette.accent : StrandPalette.textSecondary)
        .disabled(!isEnabled)
        .accessibilityIdentifier(id)
    }
}

// MARK: Treadmill

private struct PFNeedsTreadmillRow: View {
    let item: PFNeedsItem

    @EnvironmentObject private var model: PFModel
    @State private var useKmh = true
    @State private var value = ""
    @State private var incline = ""

    private var run: PFTreadmillRun? { item.run }
    private var activityID: String { item.activityID ?? "" }

    private var check: PFTreadmillInput.Result {
        guard let run else { return .init(answer: nil, hint: nil) }
        return PFTreadmillInput.check(run: run, activityID: activityID, useKmh: useKmh, value: value, incline: incline)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PFNeedsHeader(item: item)
            Picker("Unit", selection: $useKmh) {
                Text("km/h").tag(true)
                Text("min/km").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("pf-needs-unit-\(item.id)")
            HStack(spacing: 10) {
                field(useKmh ? "belt km/h" : "pace m:ss", text: $value, id: "pf-needs-speed-\(item.id)")
                field("incline %", text: $incline, id: "pf-needs-incline-\(item.id)")
            }
            if let hint = check.hint {
                Text(hint)
                    .font(StrandFont.caption)
                    .foregroundStyle(PFColor.warning)
                    .accessibilityIdentifier("pf-needs-hint-\(item.id)")
            }
            PFNeedsButton(title: "Save", prominent: true, isEnabled: check.answer != nil, id: "pf-needs-save-\(item.id)") {
                if let answer = check.answer { send(model, answer, for: item) }
            }
            HStack(spacing: 10) {
                if let last = run?.last {
                    PFNeedsButton(title: "Same as last treadmill run", id: "pf-needs-same-\(item.id)") {
                        send(model, .sameAsLast(activityID: activityID, last: last,
                                                preferBlocks: run?.structured == true), for: item)
                    }
                }
                PFNeedsButton(title: "Don't know", id: "pf-needs-unknown-\(item.id)") {
                    send(model, .treadmillUnknown(activityID: activityID), for: item)
                }
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, id: String) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numbersAndPunctuation)
            .textFieldStyle(.plain)
            .font(StrandFont.body)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceInset))
            .accessibilityIdentifier(id)
    }
}

// MARK: Proposal

private struct PFNeedsProposalRow: View {
    let item: PFNeedsItem

    @EnvironmentObject private var model: PFModel

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(item.meaning ?? item.title)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Accept") { answer(true) }
                .buttonStyle(.bordered)
                .tint(StrandPalette.accent)
                .accessibilityIdentifier("pf-needs-accept-\(item.id)")
            Button("Dismiss") { answer(false) }
                .buttonStyle(.bordered)
                .tint(StrandPalette.textSecondary)
                .accessibilityIdentifier("pf-needs-dismiss-\(item.id)")
        }
    }

    private func answer(_ accept: Bool) {
        guard let id = item.proposalID else { return }
        send(model, .proposal(id: id, accept: accept), for: item)
    }
}

// MARK: Effort 1-10 and feel 1-5

private struct PFNeedsScaleRow: View {
    let item: PFNeedsItem
    let values: [Int]
    let columns: Int
    let prefix: String

    @EnvironmentObject private var model: PFModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PFNeedsHeader(item: item)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button { answer(value) } label: {
                        Text("\(value)")
                            .font(StrandFont.rounded(20))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceInset))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(StrandPalette.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(prefix == "rpe" ? "Effort \(value) of 10" : "Feel \(value) of 5")
                    .accessibilityIdentifier("pf-needs-\(prefix)-\(value)-\(item.id)")
                }
            }
        }
    }

    private func answer(_ value: Int) {
        switch item.kind {
        case .rpe: send(model, .rpe(value, activityID: item.activityID, sessionID: item.sessionID), for: item)
        default: send(model, .feel(value, date: item.feelDate), for: item)
        }
    }
}
