#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - My Dashboard (Today)
//
// The user's own short list of metrics as today-versus-30-days rows, with CUSTOMIZE: drag the handles to reorder, remove a row,
// add one from the list, SAVE. The list is the user's, kept on the phone (`MyDashboardPrefs`); every figure is read from the same
// daily series the rest of the app reads (`Repository.exploreSeries`), so nothing is scored or stored here. Charge, Effort and
// Rest respect Hide numbers, and weight respects its own switch.

struct LookMyDashboardSection: View {
    let day: Date

    @EnvironmentObject private var repo: Repository
    @AppStorage(MyDashboardPrefs.storageKey) private var raw = MyDashboardPrefs.defaultCSV
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(HideScoresPrefs.scoresKey) private var hideScores = false
    @AppStorage(HideScoresPrefs.bodyKey) private var hideBody = false

    @State private var rows: [LookCompareRow] = []
    @State private var loaded = false
    @State private var showEditor = false

    private var ids: [String] { MyDashboardPrefs.decode(raw) }

    private var loadKey: String {
        "\(repo.refreshSeq)|\(raw)|\(effortScaleRaw)|\(unitSystemRaw)|\(hideScores)|\(hideBody)|\(Int(day.timeIntervalSince1970))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !rows.isEmpty {
                TodayVs30Rows(rows: rows)
                    .accessibilityIdentifier("look-dashboard-rows")
            } else if loaded {
                LookInfoCard(title: ids.isEmpty ? "Choose your metrics" : "Nothing to compare yet",
                             message: ids.isEmpty
                                ? "Customize to add the metrics you want to see against your last 30 days."
                                : "These rows fill in as soon as the readings behind them arrive.")
                    .accessibilityIdentifier("look-dashboard-empty")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("look-my-dashboard")
        .task(id: loadKey) { await load() }
        .sheet(isPresented: $showEditor) {
            LookDashboardEditor(initial: ids) { saved in
                raw = MyDashboardPrefs.encode(saved)
                showEditor = false
            } onCancel: { showEditor = false }
        }
    }

    private var header: some View {
        HStack {
            Text("My Dashboard")
                .font(LookFont.text(22, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
            Spacer(minLength: 8)
            Button { showEditor = true } label: {
                HStack(spacing: 6) {
                    Text("CUSTOMIZE").lookCaps(12)
                    Image(systemName: "pencil").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(NoopLook.textPrimary)
                .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize My Dashboard")
            .accessibilityIdentifier("look-dashboard-customize")
        }
    }

    // MARK: Rows

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    /// A reading as the row prints it. Effort arrives already on the display scale (see `load`), so it is only rounded here.
    private func format(_ metric: MetricDescriptor, _ value: Double) -> String {
        if metric.key == HeroRingMetric.effort { return LookFormat.number(value, decimals: effortScale == .whoop ? 1 : 0) }
        if metric.key == "weight" { return UnitFormatter.massFromKilograms(value, system: unitSystem) }
        switch metric.unit {
        case "min": return LookFormat.hoursMinutes(minutes: Int(value.rounded()))
        case "%": return "\(Int(value.rounded()))%"
        default:
            if metric.key == "steps" {
                let f = NumberFormatter()
                f.numberStyle = .decimal
                f.maximumFractionDigits = 0
                return f.string(from: NSNumber(value: value.rounded())) ?? String(Int(value.rounded()))
            }
            return LookFormat.number(value, decimals: metric.decimals)
        }
    }

    @MainActor private func load() async {
        let calendar = Calendar.current
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        var built: [LookCompareRow] = []
        for id in ids {
            let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let metric = MetricCatalog.metric(key: parts[1], source: parts[0]) else { continue }
            let series = await repo.exploreSeries(key: metric.key, source: metric.source, days: 120)
            let points = LookSeries.points(series, calendar: calendar).filter { $0.date < endOfDay }
            let scaled = metric.key == HeroRingMetric.effort
                ? points.map { LookPoint(date: $0.date, value: UnitFormatter.effortValue($0.value, scale: effortScale)) }
                : points
            let decimals = metric.key == HeroRingMetric.effort ? (effortScale == .whoop ? 1 : 0) : metric.decimals
            guard let c = LookBaseline.comparison(scaled, decimals: decimals, higherIsBetter: metric.higherIsBetter,
                                                  calendar: calendar) else { continue }
            let hidden = HideScoresPrefs.hides(key: metric.key, scores: hideScores, body: hideBody)
            built.append(LookCompareRow(
                id: id, icon: metric.icon, label: metric.title,
                valueText: hidden ? HideScoresPrefs.placeholder : format(metric, c.value),
                baselineText: hidden ? nil : c.baseline.map { format(metric, $0) },
                mark: hidden ? nil : c.mark))
        }
        guard !Task.isCancelled else { return }
        rows = built
        loaded = true
    }
}

// MARK: - The editor

/// CUSTOMIZE DASHBOARD: the chosen rows with drag handles and a remove control, the rest of the metrics to add, and SAVE.
struct LookDashboardEditor: View {
    let initial: [String]
    let onSave: ([String]) -> Void
    let onCancel: () -> Void

    @State private var draft: [String]

    init(initial: [String], onSave: @escaping ([String]) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onSave = onSave
        self.onCancel = onCancel
        self._draft = State(initialValue: initial)
    }

    private func title(_ id: String) -> String {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let metric = MetricCatalog.metric(key: parts[1], source: parts[0]) else { return id }
        return metric.title
    }

    private func icon(_ id: String) -> String {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let metric = MetricCatalog.metric(key: parts[1], source: parts[0]) else { return "chart.xyaxis.line" }
        return metric.icon
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close without saving")
                .accessibilityIdentifier("look-dashboard-close")
                Spacer()
                Text("CUSTOMIZE DASHBOARD").lookCaps(14).foregroundStyle(NoopLook.textPrimary)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)
            List {
                Section {
                    ForEach(draft, id: \.self) { id in
                        row(id)
                    }
                    .onMove { from, to in
                        guard let source = from.first else { return }
                        draft = MyDashboardPrefs.moving(draft, from: source, to: to > source ? to - 1 : to)
                    }
                    .onDelete { offsets in
                        for index in offsets.sorted(by: >) where draft.indices.contains(index) { draft.remove(at: index) }
                    }
                } header: {
                    Text("SHOWN").lookCaps(11).foregroundStyle(NoopLook.textTertiary)
                }
                let more = MyDashboardPrefs.available(excluding: draft)
                if !more.isEmpty {
                    Section {
                        ForEach(more, id: \.self) { id in
                            Button { draft = MyDashboardPrefs.adding(id, to: draft) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "plus.circle.fill").foregroundStyle(NoopLook.trendUp)
                                    Text(title(id)).lookCaps(12.5).foregroundStyle(NoopLook.textPrimary)
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(RoundedRectangle(cornerRadius: NoopLook.Metric.rowRadius, style: .continuous).fill(NoopLook.tile).padding(.vertical, 3))
                            .listRowSeparator(.hidden)
                            .accessibilityLabel("Add \(title(id))")
                            .accessibilityIdentifier("look-dashboard-add-\(id)")
                        }
                    } header: {
                        Text("+ ADD A METRIC").lookCaps(11).foregroundStyle(NoopLook.textTertiary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .containerIdentifier("look-dashboard-list")
            Button { onSave(draft) } label: {
                Text("SAVE")
                    .lookCaps(14)
                    .foregroundStyle(Color(hex: "#6E9CFF"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .overlay(Capsule(style: .continuous).stroke(Color(hex: "#6E9CFF"), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .accessibilityIdentifier("look-dashboard-save")
        }
        .lookScreenBackground()
        .presentationDragIndicator(.visible)
    }

    private func row(_ id: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon(id))
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(NoopLook.textSecondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title(id)).lookCaps(12.5).foregroundStyle(NoopLook.textPrimary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .listRowBackground(RoundedRectangle(cornerRadius: NoopLook.Metric.rowRadius, style: .continuous).fill(NoopLook.tile).padding(.vertical, 3))
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("look-dashboard-row-\(id)")
    }
}

#if DEBUG
#Preview("My Dashboard") {
    ScrollView {
        LookMyDashboardSection(day: Date())
            .padding(16)
    }
    .lookScreenBackground()
    .environmentObject(Repository(deviceId: "preview"))
    .preferredColorScheme(.dark)
}

#Preview("Dashboard editor") {
    LookDashboardEditor(initial: MyDashboardPrefs.defaultIDs, onSave: { _ in }, onCancel: {})
        .preferredColorScheme(.dark)
}
#endif
#endif
