import SwiftUI
import StrandDesign

/// "Log a simulation" under the race simulations card: when it was, the run times and the station times. Plain text boxes; the server
/// reads the times and says in words which one it cannot (`hyrox-sim-add`).
struct PFSimLogButton: View {
    @State private var showsSheet = false

    var body: some View {
        Button {
            showsSheet = true
        } label: {
            Label("Log a simulation", systemImage: "plus.circle")
                .font(StrandFont.subhead.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(StrandPalette.accent)
        .accessibilityIdentifier("pf-sim-log")
        .sheet(isPresented: $showsSheet) { PFSimLogSheet() }
    }
}

struct PFSimLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: PFModel
    @StateObject private var tracker = PFJobTracker()
    @State private var date = Date()
    @State private var runs = ""
    @State private var stations = ""
    @State private var roxzone = ""

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }
    private var inputs: [String: Any]? {
        PFJobInputs.hyroxSim(date: PFFormat.isoString(date), runs: runs, stations: stations, roxzone: roxzone)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PFCard(String(localized: "Log a simulation"), icon: "stopwatch") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Times as m:ss, in race order, with commas or spaces between. Stations: SkiErg, Sled Push, Sled Pull, Burpee Broad Jump, Row, Farmers Carry, Sandbag Lunges, Wall Balls. Fewer times log a half simulation.")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                                .font(StrandFont.subhead)
                            TextField("Run times (up to 8)", text: $runs)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numbersAndPunctuation)
                                .accessibilityIdentifier("pf-sim-runs")
                            TextField("Station times (up to 8)", text: $stations)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numbersAndPunctuation)
                                .accessibilityIdentifier("pf-sim-stations")
                            TextField("Roxzone total (optional)", text: $roxzone)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numbersAndPunctuation)
                                .accessibilityIdentifier("pf-sim-roxzone")
                            Button {
                                Task { await log() }
                            } label: {
                                Text("Log simulation")
                                    .font(StrandFont.subhead.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(StrandPalette.accent)
                            .disabled(isBusy || inputs == nil)
                            .accessibilityIdentifier("pf-sim-submit")
                            status
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Race simulations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                }
            }
        }
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
            Text("Logged. The comparison with your goal shows after PaceForge's next update.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .idle:
            EmptyView()
        }
    }

    @MainActor private func log() async {
        guard let inputs else { return }
        if case .success = await tracker.run(.hyroxSimAdd, inputs: inputs) {
            runs = ""
            stations = ""
            roxzone = ""
            await model.refresh()
        }
    }
}
