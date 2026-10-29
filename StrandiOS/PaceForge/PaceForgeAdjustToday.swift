import SwiftUI
import StrandDesign

/// "Adjust today" on NOOP Today, under My Plan: Tired, Sick, or a shorter session of 30, 45 or 60 minutes. One tap asks PaceForge to
/// change today's session (`adjust-today`, a job that runs at once), and the card says in one line what it did.
struct PFAdjustTodayCard: View {
    private struct Option {
        let id: String
        let label: LocalizedStringKey
        let mode: PFAdjustMode
    }

    private static let options: [Option] = [
        Option(id: "tired", label: "Tired", mode: .tired),
        Option(id: "sick", label: "Sick", mode: .sick),
        Option(id: "30", label: "30 min", mode: .minutes(30)),
        Option(id: "45", label: "45 min", mode: .minutes(45)),
        Option(id: "60", label: "60 min", mode: .minutes(60)),
    ]

    @StateObject private var tracker = PFJobTracker()
    @State private var confirmation: String?

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        PFCard(String(localized: "Adjust today"), icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ask PaceForge to change today's session.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach(Self.options, id: \.id) { option in chip(option) }
                }
                status
            }
        }
        .containerIdentifier("pf-adjust-today")
    }

    private func chip(_ option: Option) -> some View {
        Button {
            Task { await adjust(option.mode) }
        } label: {
            Text(option.label)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceInset))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityIdentifier("pf-adjust-\(option.id)")
    }

    @ViewBuilder private var status: some View {
        switch tracker.phase {
        case .sending, .working:
            Text("Working on it")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        case .failed(let message):
            Text(message)
                .font(StrandFont.caption)
                .foregroundStyle(PFColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        case .done:
            if let confirmation {
                Text(PFFormat.capitalized(confirmation))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pf-adjust-result")
            }
        case .idle:
            EmptyView()
        }
    }

    @MainActor private func adjust(_ mode: PFAdjustMode) async {
        guard let inputs = PFJobInputs.adjustToday(mode) else { return }
        confirmation = nil
        if case .success(let result) = await tracker.run(.adjustToday, inputs: inputs) {
            confirmation = PFAdjustToday.confirmation(result)
            // The revised session reaches the plan on the next load.
            await PFUnified.model.refresh()
        }
    }
}
