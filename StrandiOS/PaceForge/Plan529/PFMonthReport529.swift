import SwiftUI
import StrandDesign

/// The monthly report (P3), short first: one verdict, what held and what slipped, four numbers against the month before, one trend chart
/// and the focus for the next month. The existing monthly detail sits behind a row. A report without a `short` block shows the existing
/// reading screen directly.
struct PFMonthReport529: View {
    let key: String

    @StateObject private var store: PFDocStore529<PFMonthlyShort.Document>

    init(key: String) {
        self.key = key
        _store = StateObject(wrappedValue: PFDocStore529<PFMonthlyShort.Document>(path: PFDocPath529.monthlyReport(key),
                                                                                    isEmpty: { $0.short == nil }))
    }

    var body: some View {
        Group {
            switch store.state {
            case .loading:
                PFDocPlaceholder529(kind: .loading).planScreen529(title: "Month report", identifier: "plan529-month-report")
            case .failed:
                PFDocPlaceholder529(kind: .failed, retry: { Task { await store.refresh() } })
                    .planScreen529(title: "Month report", identifier: "plan529-month-report")
            case .empty:
                PFReportsScreen(kind: .monthly)
            case .loaded(let doc):
                PFMonthShortView529(short: doc.short ?? PFMonthlyShort())
                    .planScreen529(title: doc.short?.title ?? "Month report", identifier: "plan529-month-report")
            }
        }
        .task { await store.refreshIfStale() }
    }
}

struct PFMonthShortView529: View {
    let short: PFMonthlyShort

    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if let verdict = short.verdict {
                    Text(hiding.text(verdict))
                        .font(LookFont.text(22, weight: .bold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("month-verdict")
                }
                if let summary = short.summary {
                    Text(hiding.text(summary))
                        .font(LookFont.text(14.5))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PFStoryBlocks529(story: short.story, insights: (short.insights ?? []).prefix(3).map { (title: $0.title ?? "", text: $0.text ?? "") })
            }
            .planCard529()
            if !(short.held ?? []).isEmpty || !(short.slipped ?? []).isEmpty { heldSlippedCard }
            if let tiles = short.tiles, !tiles.isEmpty { tilesCard(tiles) }
            if let points = short.trend?.points, !points.isEmpty { trendCard(points) }
            if let focus = short.focus {
                VStack(alignment: .leading, spacing: 4) {
                    PFOver529(text: short.focusTitle ?? "Next month")
                    Text(hiding.text(focus))
                        .font(LookFont.text(14.5))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .planCard529()
                .accessibilityIdentifier("month-focus")
            }
            linksCard
        }
    }

    private var heldSlippedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let held = short.held, !held.isEmpty { list("Held", lines: held, color: NoopLook.trendUp) }
            if let slipped = short.slipped, !slipped.isEmpty { list("Slipped", lines: slipped, color: NoopLook.trendDown) }
        }
        .planCard529()
        .containerIdentifier("month-held-slipped")
    }

    private func list(_ title: String, lines: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .lookCaps(10.5, weight: .semibold)
                .foregroundStyle(color)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(hiding.text(line))
                    .font(LookFont.text(14))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tilesCard(_ tiles: [PFMonthlyShort.Tile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PFOver529(text: short.compareTitle ?? "Against the month before")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    PFTile529(value: hiding.text(tile.value ?? "\u{2013}"),
                              sub: [tile.label, tile.sub].compactMap { $0 }.map { hiding.text($0) }.joined(separator: "\n"))
                }
            }
        }
        .planCard529()
        .containerIdentifier("month-tiles")
    }

    private func trendCard(_ points: [PFMonthlyShort.Point]) -> some View {
        let top = max(1, points.compactMap { $0.value }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            PFOver529(text: short.trend?.title ?? "Trend")
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(PFColor.sky)
                        .frame(height: max(2, CGFloat((point.value ?? 0) / top) * 52))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 52, alignment: .bottom)
            HStack(spacing: 5) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Text(point.value.map { PFFormat.trimmed($0) } ?? "")
                        .font(LookFont.text(10))
                        .foregroundStyle(NoopLook.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 5) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Text(point.label ?? "")
                        .font(LookFont.text(10))
                        .foregroundStyle(NoopLook.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .planCard529()
        .containerIdentifier("month-trend")
    }

    private var linksCard: some View {
        VStack(spacing: 0) {
            NavigationLink(value: TabRoute.reports("monthly")) {
                PFRow529(title: "Training, body and race detail", showsChevron: true).padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("month-detail")
            PFDivider529()
            NavigationLink(value: TabRoute.monthlyReport) {
                PFRow529(title: "Charge, Effort and Rest for the month", showsChevron: true).padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("month-scores")
        }
        .planCard529(padding: 0)
    }
}
