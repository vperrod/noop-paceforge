import SwiftUI
import StrandDesign

/// W4, when the day does not go to plan: one sheet for the four tools that sat in four places: Adjust today, Easy mode, Niggles and the
/// coach's "change my plan". Every function is the one it was: the same jobs (`adjust-today`, `easy-mode`, `easy-mode-end`, a proposal's
/// answer, `niggle-add`, `niggle-resolve`, `coach`) and the same identifiers.
struct PFChangeTodaySheet529: View {
    @ObservedObject private var model = PFUnified.model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PFTodayOnly529()
                PFEasyModePanel529(easy: model.snapshot?.easyMode)
                PFNigglePanel529()
                VStack(alignment: .leading, spacing: 10) {
                    PFWeekOverline529(text: "Or say it")
                    PFWeekTellCoach529(idPrefix: "plan529-say")
                }
                .pfWeekCard()
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .lookScreenBackground()
        .navigationTitle("Change today")
        .navigationBarTitleDisplayMode(.inline)
        // The easy-mode Accept and End buttons read the model from the environment.
        .environmentObject(model)
        .containerIdentifier("plan529-change-today")
        .task { await model.refreshIfStale() }
    }
}

// MARK: Today only

/// Tired, Short on time (30, 45 or 60 minutes) and Sick: one tap asks PaceForge to change today's session (`adjust-today`, a job that
/// runs at once) and the card says in one line what it did.
private struct PFTodayOnly529: View {
    @StateObject private var tracker = PFJobTracker()
    @State private var confirmation: String?

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: "Today only")
            row(title: "Tired", sub: "The session at two thirds: shorter and easier", id: "tired") {
                Task { await adjust(.tired) }
            }
            Divider().overlay(NoopLook.divider)
            VStack(alignment: .leading, spacing: 8) {
                titleBlock("Short on time", "30, 45 or 60 minutes. The key part is kept.")
                LookFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach([30, 45, 60], id: \.self) { minutes in
                        PFWeekButton529(title: "\(minutes) min", isDisabled: isBusy, identifier: "pf-adjust-\(minutes)") {
                            Task { await adjust(.minutes(minutes)) }
                        }
                    }
                }
            }
            Divider().overlay(NoopLook.divider)
            row(title: "Sick", sub: "20 minutes, very easy, or nothing", id: "sick") {
                Task { await adjust(.sick) }
            }
            status
        }
        .pfWeekCard()
        .containerIdentifier("pf-adjust-today")
    }

    private func titleBlock(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(LookFont.text(15, weight: .semibold)).foregroundStyle(NoopLook.textPrimary)
            PFWeekSub529(text: sub)
        }
    }

    private func row(title: String, sub: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                titleBlock(title, sub)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityIdentifier("pf-adjust-\(id)")
    }

    @ViewBuilder private var status: some View {
        switch tracker.phase {
        case .sending, .working:
            PFWeekSub529(text: "Working on it")
        case .failed(let message):
            Text(message)
                .font(LookFont.text(12.5, weight: .regular))
                .foregroundStyle(PFWeekColor529.amber)
                .fixedSize(horizontal: false, vertical: true)
        case .done:
            if let confirmation {
                Text(PFFormat.capitalized(confirmation))
                    .font(LookFont.text(14, weight: .regular))
                    .foregroundStyle(NoopLook.textSecondary)
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
            await PFUnified.model.refresh()
            NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
        }
    }
}

// MARK: Easy mode

/// Not feeling 100 %, for several days: start (Lighter / Less / Rest-ish for 3 to 14 days), and while a mode is on or proposed its card
/// with Accept and End easy mode.
private struct PFEasyModePanel529: View {
    let easy: PFEasyMode?

    @EnvironmentObject private var model: PFModel
    @StateObject private var tracker = PFJobTracker()
    @State private var level = PFEasyModeJobs.defaultLevel
    @State private var days = PFEasyModeJobs.defaultDays
    @State private var note: String?

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        if let easy, !easy.isIdle {
            PFEasyModeCard(easy: easy)
        } else {
            start
        }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: "Not feeling 100 %, for several days")
            LookFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(PFEasyLevel.allCases, id: \.rawValue) { option in levelChip(option) }
            }
            PFWeekSub529(text: "Lighter: no pace targets. Less: a quarter less, easy only. Rest-ish: walks and mobility. For 3 to 14 days, then the plan comes back by itself.")
            Stepper(value: $days, in: PFEasyModeJobs.days) {
                Text("For \(days) days").font(LookFont.text(14.5, weight: .medium)).foregroundStyle(NoopLook.textPrimary)
            }
            PFWeekButton529(title: "Start easy mode", isProminent: true, isDisabled: isBusy, identifier: "pf-easy-start") {
                Task { await begin() }
            }
            status
        }
        .pfWeekCard()
        .containerIdentifier("pf-easy-start-card")
    }

    private func levelChip(_ option: PFEasyLevel) -> some View {
        let isSelected = level == option
        return Button { level = option } label: {
            Text(Self.label(option))
                .lookCaps(11, weight: .semibold)
                .foregroundStyle(isSelected ? Color(hex: "#06231A") : NoopLook.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Capsule(style: .continuous).fill(isSelected ? PFWeekColor529.teal : Color.clear))
                .overlay(Capsule(style: .continuous).stroke(isSelected ? PFWeekColor529.teal : NoopLook.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.label(option))
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier("pf-easy-level-\(option.rawValue)")
    }

    private static func label(_ option: PFEasyLevel) -> String {
        switch option {
        case .light: return "Lighter"
        case .reduce: return "Less"
        case .restish: return "Rest-ish"
        }
    }

    @ViewBuilder private var status: some View {
        switch tracker.phase {
        case .sending, .working:
            PFWeekSub529(text: "Working on it")
        case .failed(let message):
            Text(message)
                .font(LookFont.text(12.5, weight: .regular))
                .foregroundStyle(PFWeekColor529.amber)
                .fixedSize(horizontal: false, vertical: true)
        case .done:
            if let note { PFWeekSub529(text: note).accessibilityIdentifier("pf-easy-note") }
        case .idle:
            EmptyView()
        }
    }

    @MainActor private func begin() async {
        guard let inputs = PFJobInputs.easyMode(level: level, days: days) else { return }
        note = nil
        if case .success(let result) = await tracker.run(.easyMode, inputs: inputs) {
            note = PFEasyModeJobs.filedLine(result)
            await model.refresh()
        }
    }
}

// MARK: Niggles

/// Something hurts: the open niggles (each with Resolved) and a new one (where, how bad, Log it). No daily prompt asks for either.
private struct PFNigglePanel529: View {
    @StateObject private var tracker = PFJobTracker()
    @State private var niggles: [PFNiggle] = []
    @State private var site: PFNiggleSite?
    @State private var severity: Int?
    @State private var loaded = false
    /// The list could not be read: it says so, with a way to try again, instead of claiming that no niggle is open.
    @State private var loadFailed = false

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: "Something hurts")
            openRows
            LookFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(PFNiggleSite.allCases, id: \.rawValue) { option in siteChip(option) }
            }
            PFWeekSub529(text: "How bad? 1 is barely there, 5 stops you training. The coach then proposes easier versions of the sessions that load it, for the next 7 days.")
            LookFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(1...5, id: \.self) { level in severityChip(level) }
            }
            PFWeekButton529(title: "Log it", isProminent: true, isDisabled: isBusy || site == nil || severity == nil,
                            identifier: "pf-niggle-log") {
                Task { await add() }
            }
            if case .failed(let message) = tracker.phase {
                Text(message)
                    .font(LookFont.text(12.5, weight: .regular))
                    .foregroundStyle(PFWeekColor529.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .pfWeekCard()
        .containerIdentifier("pf-niggles-log")
        .task { await load() }
    }

    @ViewBuilder private var openRows: some View {
        let open = PFNiggles.open(niggles)
        if loadFailed {
            HStack(spacing: 10) {
                PFWeekSub529(text: "The open niggles could not be loaded.").accessibilityIdentifier("pf-niggles-failed")
                Spacer(minLength: 8)
                PFWeekButton529(title: "Try again", identifier: "pf-niggles-retry") { Task { await load() } }
            }
        } else if loaded && open.isEmpty {
            PFWeekSub529(text: "No niggle is open.").accessibilityIdentifier("pf-niggles-none")
        }
        ForEach(open) { niggle in
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(PFFormat.capitalized(niggle.site)).font(LookFont.text(15, weight: .semibold)).foregroundStyle(NoopLook.textPrimary)
                    PFWeekSub529(text: [niggle.severity.map { "\($0)/5" }, niggle.date].compactMap { $0 }.joined(separator: " \u{00B7} "))
                }
                Spacer(minLength: 8)
                PFWeekButton529(title: "Resolved", isDisabled: isBusy, identifier: "pf-niggle-resolve-\(niggle.id)") {
                    Task { await resolve(niggle) }
                }
            }
        }
    }

    private func siteChip(_ option: PFNiggleSite) -> some View {
        chip(selected: site == option, title: Self.label(option), id: "pf-niggle-site-\(option.rawValue)") { site = option }
    }

    private func severityChip(_ level: Int) -> some View {
        chip(selected: severity == level, title: String(level), id: "pf-niggle-severity-\(level)") { severity = level }
    }

    private func chip(selected: Bool, title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lookCaps(11, weight: .semibold)
                .foregroundStyle(selected ? Color(hex: "#06231A") : NoopLook.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Capsule(style: .continuous).fill(selected ? PFWeekColor529.teal : Color.clear))
                .overlay(Capsule(style: .continuous).stroke(selected ? PFWeekColor529.teal : NoopLook.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityIdentifier(id)
    }

    private static func label(_ option: PFNiggleSite) -> String {
        switch option {
        case .knee: return "Knee"
        case .calf: return "Calf"
        case .achilles: return "Achilles"
        case .hamstring: return "Hamstring"
        case .hip: return "Hip"
        case .back: return "Back or spine"
        case .shoulder: return "Shoulder"
        case .other: return "Other"
        }
    }

    @MainActor private func load() async {
        let fetched = await PFAPI.fetchDoc("data/niggles.json")
        if let data = fetched.data {
            niggles = PFNiggles.list(data)
            loadFailed = false
        } else {
            // Not served is an empty list; a failed read with no saved copy is not.
            loadFailed = fetched.failed
        }
        loaded = true
    }

    @MainActor private func add() async {
        guard let site, let severity, let inputs = PFJobInputs.niggleAdd(site: site, severity: severity) else { return }
        guard case .success(let result) = await tracker.run(.niggleAdd, inputs: inputs) else { return }
        if let added = PFNiggles.row(result) {
            niggles.removeAll { $0.id == added.id }
            niggles.append(added)
        }
        self.site = nil
        self.severity = nil
    }

    @MainActor private func resolve(_ niggle: PFNiggle) async {
        guard let inputs = PFJobInputs.niggleResolve(id: niggle.id) else { return }
        guard case .success = await tracker.run(.niggleResolve, inputs: inputs) else { return }
        niggles.removeAll { $0.id == niggle.id }
    }
}
