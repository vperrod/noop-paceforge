import SwiftUI
import StrandDesign

// The Coach screen's "Coach log" card: what the coach said and did, from `api/coach-log`. Read-only.

@MainActor
final class PFCoachLogStore: ObservableObject {
    static let shared = PFCoachLogStore()

    static let path = "api/coach-log"

    enum Phase: Equatable { case loading, loaded, failed }

    @Published private(set) var entries: [PFCoachLogEntry] = []
    @Published private(set) var phase: Phase = .loading

    private var lastFetch: Date?
    private var inFlight: Task<Void, Never>?

    func refreshIfStale() async {
        if let lastFetch, phase == .loaded, Date().timeIntervalSince(lastFetch) < 60 { return }
        await refresh()
    }

    /// Overlapping callers share the load already running.
    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { [self] in
            await load()
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    private func load() async {
        guard PFAPI.isConfigured else {
            phase = .loaded
            return
        }
        do {
            let data = try await PFAPI.fetch(Self.path)
            let parsed = PFCoachLog.parse(data)
            if entries != parsed { entries = parsed }
            lastFetch = Date()
            phase = .loaded
        } catch {
            // Keep the rows already on screen; only a first load with nothing to show reads as failed.
            if entries.isEmpty { phase = .failed }
        }
    }
}

struct PFCoachLogCard: View {
    @ObservedObject private var store = PFCoachLogStore.shared
    @State private var showsFourteenDays = false
    @State private var expanded: Set<String> = []

    var body: some View {
        if PFAPI.isConfigured {
            PFCard("Coach log", icon: "list.bullet.rectangle") {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
            }
            .accessibilityIdentifier("coach-log")
        }
    }

    @ViewBuilder private var content: some View {
        let days = PFCoachLog.days(store.entries, last: showsFourteenDays ? 14 : 3)
        if store.phase == .loading && store.entries.isEmpty {
            ProgressView()
        } else if store.phase == .failed {
            Text("The coach log could not be loaded")
                .font(StrandFont.subhead)
                .foregroundStyle(PFColor.warning)
        } else if days.isEmpty {
            Text(showsFourteenDays ? "Nothing in the coach log for the last 14 days."
                                   : "Nothing in the coach log for the last 3 days.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
        } else {
            ForEach(days) { day in
                VStack(alignment: .leading, spacing: 10) {
                    Text(day.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                    ForEach(day.entries) { entry in row(entry) }
                }
            }
        }
        if !showsFourteenDays, store.phase == .loaded {
            Button("Show 14 days") { showsFourteenDays = true }
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.accent)
                .buttonStyle(.plain)
        }
    }

    private func row(_ entry: PFCoachLogEntry) -> some View {
        let isOpen = expanded.contains(entry.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.clock.string(from: entry.date))
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text(entry.kindLabel)
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(Self.color(entry.kind))
            }
            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !entry.text.isEmpty {
                if isOpen {
                    PFMarkdown(text: entry.text)
                } else {
                    Text(entry.text)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !entry.text.isEmpty else { return }
            if isOpen { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
        }
        .accessibilityElement(children: .combine)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func color(_ kind: String) -> Color {
        switch kind {
        case "failure", "alert": return PFColor.critical
        case "proposal", "change": return PFColor.warning
        case "decision": return PFColor.positive
        case "brief", "pulse", "review": return StrandPalette.accent
        case "analysis": return PFColor.violet
        default: return PFColor.sky
        }
    }
}
