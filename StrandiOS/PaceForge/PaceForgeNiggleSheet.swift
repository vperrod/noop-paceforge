import SwiftUI
import StrandDesign

/// "Niggles" on Today, under My Plan: how many are open, and a tap opens the sheet where one is logged or marked resolved.
struct PFNiggleEntryCard: View {
    @State private var openCount: Int?
    @State private var showsSheet = false

    var body: some View {
        Button {
            showsSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bandage")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NoopLook.textSecondary)
                Text("Niggles")
                    .lookCaps(12.5)
                    .foregroundStyle(NoopLook.textPrimary)
                Spacer(minLength: 8)
                summary
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pf-niggles-entry")
        .task { await load() }
        .sheet(isPresented: $showsSheet, onDismiss: { Task { await load() } }) {
            PFNiggleSheet()
        }
    }

    @ViewBuilder private var summary: some View {
        if let openCount, openCount > 0 {
            Text("\(openCount) open")
                .font(StrandFont.caption)
                .foregroundStyle(PFColor.warning)
        } else if openCount != nil {
            Text("None open")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    @MainActor private func load() async {
        guard let data = await PFAPI.fetchOptional("data/niggles.json") else { return }
        openCount = PFNiggles.open(PFNiggles.list(data)).count
    }
}

/// Log a niggle (an area and how bad, two taps and Log) or mark an open one resolved (one tap). No daily prompt asks for either.
struct PFNiggleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tracker = PFJobTracker()
    @State private var niggles: [PFNiggle] = []
    @State private var site: PFNiggleSite?
    @State private var severity: Int?
    @State private var loaded = false

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    openCard
                    logCard
                    status
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Niggles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                }
            }
        }
        .task { await load() }
    }

    // MARK: Open niggles

    private var openCard: some View {
        PFCard(String(localized: "Open niggles"), icon: "bandage") {
            VStack(alignment: .leading, spacing: 8) {
                if PFNiggles.open(niggles).isEmpty {
                    emptyLine
                }
                ForEach(PFNiggles.open(niggles)) { niggle in openRow(niggle) }
            }
        }
        .containerIdentifier("pf-niggles-open")
    }

    @ViewBuilder private var emptyLine: some View {
        if loaded {
            Text("None open").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
        } else {
            Text("Loading").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private func openRow(_ niggle: PFNiggle) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PFFormat.capitalized(niggle.site))
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(detail(niggle))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer(minLength: 8)
            Button("Resolved") { Task { await resolve(niggle) } }
                .buttonStyle(.bordered)
                .disabled(isBusy)
                .accessibilityIdentifier("pf-niggle-resolve-\(niggle.id)")
        }
    }

    private func detail(_ niggle: PFNiggle) -> String {
        [niggle.severity.map { "\($0)/5" }, niggle.date].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    // MARK: Log one

    private var logCard: some View {
        PFCard(String(localized: "Log a niggle"), icon: "plus.circle") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Where is it?").strandOverline()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(PFNiggleSite.allCases, id: \.rawValue) { option in siteChip(option) }
                }
                Text("How bad is it?").strandOverline()
                Text("1 is barely there, 5 stops you training.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in severityChip(level) }
                }
                Button {
                    Task { await add() }
                } label: {
                    Text("Log it")
                        .font(StrandFont.subhead.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(StrandPalette.accent)
                .disabled(isBusy || site == nil || severity == nil)
                .accessibilityIdentifier("pf-niggle-log")
            }
        }
        .containerIdentifier("pf-niggles-log")
    }

    private func siteChip(_ option: PFNiggleSite) -> some View {
        chip(selected: site == option, id: "pf-niggle-site-\(option.rawValue)") {
            Text(Self.label(option))
        } action: {
            site = option
        }
    }

    private func severityChip(_ level: Int) -> some View {
        chip(selected: severity == level, id: "pf-niggle-severity-\(level)") {
            Text(String(level))
        } action: {
            severity = level
        }
    }

    private func chip<Content: View>(selected: Bool, id: String, @ViewBuilder label: () -> Content,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label()
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(selected ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? StrandPalette.accent : StrandPalette.surfaceInset))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private static func label(_ option: PFNiggleSite) -> LocalizedStringKey {
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

    @ViewBuilder private var status: some View {
        if case .failed(let message) = tracker.phase {
            Text(message)
                .font(StrandFont.caption)
                .foregroundStyle(PFColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    @MainActor private func load() async {
        if let data = await PFAPI.fetchOptional("data/niggles.json") { niggles = PFNiggles.list(data) }
        loaded = true
    }

    @MainActor private func add() async {
        guard let site, let severity, let inputs = PFJobInputs.niggleAdd(site: site, severity: severity) else { return }
        guard case .success(let result) = await tracker.run(.niggleAdd, inputs: inputs) else { return }
        if let added = PFNiggles.row(result) { niggles.removeAll { $0.id == added.id }; niggles.append(added) }
        self.site = nil
        self.severity = nil
    }

    @MainActor private func resolve(_ niggle: PFNiggle) async {
        guard let inputs = PFJobInputs.niggleResolve(id: niggle.id) else { return }
        guard case .success = await tracker.run(.niggleResolve, inputs: inputs) else { return }
        niggles.removeAll { $0.id == niggle.id }
    }
}
