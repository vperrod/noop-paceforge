import SwiftUI
import StrandDesign

/// The overview card on Today, morning or evening (screens 3a and 5d top). Mounted below the rings, metric cards and My Day graph.
/// The phone chooses the card (`PFTodayCards530.choice`): the evening card from the document's `evening_from`, or while the morning card
/// does not exist yet; otherwise the morning card. It re-reads the clock every minute. With nothing to show it draws nothing; while
/// loading and when the document cannot be fetched it says so on a slim card.
struct PFTodayOverviewCard530: View {
    @StateObject private var store = PFDocStore529<PFTodayCards530>(
        path: PFDocPath529.todayCards,
        isEmpty: { $0.morning == nil && $0.evening == nil })
    @Environment(\.scenePhase) private var scenePhase
    private let hiding = PFHiding()

    var body: some View {
        // The loader is its own always-present, zero-size view: a `.task` on content that is empty until the document has loaded can wait
        // for ever for the document it is meant to load (the same reason the journal reminder card does it this way).
        ZStack {
            Color.clear
                .frame(width: 0, height: 0)
                .task { await store.refreshIfStale() }
            content
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshIfStale() } }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading")
                    .font(LookFont.text(13.5))
                    .foregroundStyle(NoopLook.textSecondary)
            }
            .planCard529()
            .containerIdentifier("today-overview-loading")
        case .failed:
            PFDocPlaceholder529(kind: .failed, failedText: "Today's overview could not be loaded, and no saved copy is on this phone.",
                                retry: { Task { await store.refresh() } })
                .containerIdentifier("today-overview-failed")
        case .empty:
            EmptyView()
        case .loaded(let doc):
            // Re-read every minute, so the card turns into the evening card when the evening starts without the screen being reopened.
            TimelineView(.everyMinute) { context in
                card(doc, now: context.date)
            }
        }
    }

    @ViewBuilder private func card(_ doc: PFTodayCards530, now: Date) -> some View {
        switch doc.choice(minutesOfDay: Self.minutesOfDay(now), forcedEvening: Self.forcedEvening) {
        case .morning:
            if let morning = doc.morning { morningCard(morning, doc: doc) }
        case .evening:
            if let evening = doc.evening { PFTodayEveningCard530(card: evening, isStale: store.isStale) }
        case .nothing:
            EmptyView()
        }
    }

    private static func minutesOfDay(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// UI tests force the card the way the bookend row's clock is forced: `-PaceForgeEvening` / `-PaceForgeMorning` (fixture runs only).
    private static var forcedEvening: Bool? {
        #if DEBUG
        if PFAPI.isFixture {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-PaceForgeEvening") { return true }
            if arguments.contains("-PaceForgeMorning") { return false }
        }
        #endif
        return nil
    }

    // MARK: Morning (3a)

    private func reportDate(_ morning: PFTodayCards530.Morning, _ doc: PFTodayCards530) -> String {
        morning.link?.date ?? morning.date ?? doc.date ?? PFAPI.todayISO
    }

    private func morningCard(_ morning: PFTodayCards530.Morning, doc: PFTodayCards530) -> some View {
        let trends = (morning.trend ?? []).filter { !($0.values ?? []).isEmpty }
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                if let title = morning.title { PFOver529(text: hiding.text(title)) }
                if let verdict = morning.verdict {
                    Text(hiding.text(verdict))
                        .font(LookFont.text(19, weight: .bold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("today-overview-verdict")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The link is laid over the text instead of wrapping it, so the verdict stays its own accessibility element.
            .overlay {
                NavigationLink(value: TabRoute.plan529(.dailyReport(date: reportDate(morning, doc)))) { Color.clear }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Open the daily report"))
                    .accessibilityIdentifier("today-overview-open")
            }

            if let devices = morning.devices, !devices.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(devices.enumerated()), id: \.offset) { _, device in
                        deviceTile(device, band: Self.lastBand(of: device.source, in: trends))
                    }
                }
            }
            ForEach(Array(trends.enumerated()), id: \.offset) { _, trend in
                trendChart(trend)
            }
            if let reading = morning.reading {
                Text(hiding.text(reading))
                    .font(LookFont.text(13.5))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today-overview-reading")
            }
            let rows = (morning.rows ?? []).filter { !($0.text ?? "").isEmpty }
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider().overlay(NoopLook.textTertiary.opacity(0.2)) }
                        rowLink(row, date: reportDate(morning, doc))
                    }
                }
            }
            if store.isStale { PFStaleNote529() }
        }
        .planCard529()
        .containerIdentifier("today-overview-morning")
    }

    private func deviceTile(_ device: PFDailyShort.Device, band: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text([device.source, device.label.map(Self.firstWord)].compactMap { $0 }.joined(separator: " "))
                .font(LookFont.text(11, weight: .semibold))
                .foregroundStyle(NoopLook.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text(hiding.shown(device.value ?? "\u{2013}", .scores))
                .font(LookFont.numeral(24))
                .foregroundStyle(Self.color(band) ?? NoopLook.textPrimary)
            ForEach(Array((device.lines ?? []).prefix(2).enumerated()), id: \.offset) { _, line in
                Text(hiding.text(line))
                    .font(LookFont.text(11.5))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-overview-device-\(device.source ?? "")")
    }

    /// Eight bars, oldest first, each in its own colour; a night without a score is a short grey stub. Drawn from the scores, so it stays
    /// off while Hide numbers hides them.
    @ViewBuilder private func trendChart(_ trend: PFTodayCards530.Trend) -> some View {
        let values = trend.values ?? []
        let name = trend.source ?? ""
        let title = "\(Self.capitalized(trend.label ?? "Score")), last \(values.count) mornings \u{00B7} \(name)"
        if !hiding.hides(.scores) {
            VStack(alignment: .leading, spacing: 4) {
                PFOver529(text: title)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        let band = (trend.bands ?? []).indices.contains(index) ? (trend.bands ?? [])[index] : nil
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(value == nil ? NoopLook.textTertiary.opacity(0.25) : (Self.color(band) ?? NoopLook.textTertiary))
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.barHeight(value))
                    }
                }
                .frame(height: 48, alignment: .bottom)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(title))
                .accessibilityIdentifier("today-overview-trend-\(name)")
            }
        }
    }

    private func rowLink(_ row: PFTodayCards530.Row, date: String) -> some View {
        NavigationLink(value: TabRoute.plan529(.dailyReport(date: date))) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title ?? "")
                        .font(LookFont.text(14, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                    Text(hiding.text(row.text ?? ""))
                        .font(LookFont.text(12.5))
                        .foregroundStyle(NoopLook.textTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-overview-row-\(row.title ?? "")")
    }

    // MARK: Helpers

    private static func lastBand(of source: String?, in trends: [PFTodayCards530.Trend]) -> String? {
        guard let trend = trends.first(where: { $0.source == source }), let band = trend.bands?.last else { return nil }
        return band
    }

    /// "recovery, green" -> "recovery": the colour word is dropped from the tile's name (the value carries the colour).
    private static func firstWord(_ label: String) -> String {
        label.split(separator: ",").first.map(String.init) ?? label
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func barHeight(_ value: Double?) -> CGFloat {
        guard let value else { return 6 }
        return max(4, CGFloat(min(max(value, 0), 100)) / 100 * 48)
    }

    static func color(_ band: String?) -> Color? {
        switch band {
        case "green": return PFColor.positive
        case "amber": return PFColor.warning
        case "red": return PFColor.critical
        default: return nil
        }
    }
}

/// The evening card (screen 5d, top): the day against the plan, what moved, what the devices found for the journal, tonight. A tap opens the
/// evening reflection, where the day's questions are asked. Lines the document leaves out are left out.
struct PFTodayEveningCard530: View {
    let card: PFTodayCards530.Evening
    var isStale = false
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = card.title { PFOver529(text: hiding.text("Your day \u{00B7} \(title)")) }
            if let verdict = card.verdict {
                Text(hiding.text(verdict))
                    .font(LookFont.text(19, weight: .bold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today-overview-verdict")
            }
            line("Against the plan", card.againstPlan, id: "against-plan")
            line("What moved today", card.moved, id: "moved")
            if let found = card.found, !found.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found for your journal")
                        .font(LookFont.text(12, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                    PFTodayTagFlow530(spacing: 6) {
                        ForEach(Array(found.enumerated()), id: \.offset) { _, tag in
                            Text(hiding.text(tag))
                                .font(LookFont.text(12))
                                .foregroundStyle(NoopLook.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(NoopLook.row))
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today-overview-found")
            }
            line("Tonight", card.tonight, id: "tonight")
            if isStale { PFStaleNote529() }
        }
        .planCard529()
        // The link is laid over the card instead of wrapping it, so each line stays its own accessibility element.
        .overlay {
            NavigationLink(value: TabRoute.plan529(.journalEvening)) { Color.clear }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Open the evening reflection"))
                .accessibilityIdentifier("today-overview-open")
        }
        .containerIdentifier("today-overview-evening")
    }

    @ViewBuilder private func line(_ title: String, _ text: String?, id: String) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LookFont.text(12, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                Text(hiding.text(text))
                    .font(LookFont.text(13.5))
                    .foregroundStyle(NoopLook.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today-overview-\(id)")
        }
    }
}

/// Wraps its children onto lines, left to right.
struct PFTodayTagFlow530: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, CGSize(width: widest, height: y + lineHeight))
    }
}
