import SwiftUI
import StrandDesign

/// Training › Events: one row that opens the sheet where an event (a race) is added or cancelled.
struct PFEventsEntryButton: View {
    @State private var showsSheet = false

    var body: some View {
        Button {
            showsSheet = true
        } label: {
            Label("Add or cancel an event", systemImage: "flag.checkered")
                .font(StrandFont.subhead.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(StrandPalette.accent)
        .accessibilityIdentifier("pf-events-edit")
        .sheet(isPresented: $showsSheet) { PFEventsSheet() }
    }
}

/// Add an event (name, date, type, an optional place) or cancel one. `save-events` replaces the whole list, so the list is read first and
/// sent back whole with only this change; if it cannot be read, nothing can be changed.
struct PFEventsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: PFModel
    @StateObject private var tracker = PFJobTracker()
    @State private var list: [[String: Any]]?
    @State private var didLoad = false
    @State private var name = ""
    @State private var date = Date()
    @State private var type = ""
    @State private var place = ""
    @State private var problem: String?
    @State private var cancelling: PFEventRow?

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    upcomingCard
                    if list != nil { addCard }
                    status
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                }
            }
            .confirmationDialog("Cancel this event? It is removed from your list.",
                                isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
                                titleVisibility: .visible, presenting: cancelling) { event in
                Button("Cancel event", role: .destructive) { Task { await cancel(event) } }
            }
        }
        .task { await load() }
    }

    // MARK: Upcoming

    private var upcomingCard: some View {
        PFCard(String(localized: "Upcoming events"), icon: "flag.checkered") {
            VStack(alignment: .leading, spacing: 10) {
                if list == nil {
                    unreadable
                } else if upcoming.isEmpty {
                    Text("No upcoming events")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                ForEach(upcoming) { event in row(event) }
            }
        }
        .containerIdentifier("pf-events-upcoming")
    }

    private var upcoming: [PFEventRow] {
        PFEvents.rows(list ?? []).filter { $0.date >= PFAPI.todayISO }
    }

    @ViewBuilder private var unreadable: some View {
        if didLoad {
            Text("PaceForge's events could not be read, so nothing can be changed right now.")
                .font(StrandFont.subhead)
                .foregroundStyle(PFColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Loading")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private func row(_ event: PFEventRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail(event))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer(minLength: 8)
            Button("Cancel", role: .destructive) { cancelling = event }
                .buttonStyle(.bordered)
                .disabled(isBusy)
                .accessibilityIdentifier("pf-event-cancel-\(event.date)")
        }
    }

    private func detail(_ event: PFEventRow) -> String {
        [PFFormat.dayTitle(event.date), event.type].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    // MARK: Add

    private var addCard: some View {
        PFCard(String(localized: "Add an event"), icon: "plus.circle") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("pf-event-name")
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .font(StrandFont.subhead)
                TextField("Type, for example Half Marathon or HYROX", text: $type)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("pf-event-type")
                TextField("Place (optional)", text: $place)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("pf-event-place")
                Button {
                    Task { await add() }
                } label: {
                    Text("Add event")
                        .font(StrandFont.subhead.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(StrandPalette.accent)
                .disabled(isBusy)
                .accessibilityIdentifier("pf-event-add")
            }
        }
        .containerIdentifier("pf-events-add")
    }

    @ViewBuilder private var status: some View {
        if let problem {
            Text(problem)
                .font(StrandFont.caption)
                .foregroundStyle(PFColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else if case .failed(let message) = tracker.phase {
            Text(message)
                .font(StrandFont.caption)
                .foregroundStyle(PFColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    @MainActor private func load() async {
        let data = await PFAPI.fetchOptional("data/events.json")
        list = PFEvents.parse(data)
        didLoad = true
    }

    @MainActor private func add() async {
        let change = PFEventChange.add(name: name, date: PFFormat.isoString(date), type: type, location: place)
        if await apply(change) {
            name = ""
            type = ""
            place = ""
        }
    }

    @MainActor private func cancel(_ event: PFEventRow) async {
        _ = await apply(.cancel(date: event.date, name: event.name))
    }

    /// Reads the list again just before sending (the one on screen may be older than the server's), applies the single change to that
    /// fresh list and sends all of it. If the fresh list cannot be read nothing is sent: the server would replace its list with ours.
    @MainActor private func apply(_ change: PFEventChange) async -> Bool {
        problem = nil
        guard let fresh = PFEvents.parse(await PFAPI.fetchOptional("data/events.json")) else {
            problem = PFEventProblem.unreadable.message
            return false
        }
        switch PFEvents.applying(change, to: fresh) {
        case .failure(let reason):
            list = fresh
            problem = reason.message
            return false
        case .success(let updated):
            if case .cancel = change, updated.count == fresh.count {
                list = fresh
                return true
            }
            guard let inputs = PFEvents.inputs(updated) else {
                list = fresh
                problem = PFEventProblem.tooMany.message
                return false
            }
            guard case .success = await tracker.run(.saveEvents, inputs: inputs) else { return false }
            list = updated
            await model.refresh()
            return true
        }
    }
}
