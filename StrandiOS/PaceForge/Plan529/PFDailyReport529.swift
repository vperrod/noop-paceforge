import SwiftUI
import StrandDesign

/// A daily report (P2), short first: the verdict and its cause, each device on its own, today, tonight and tomorrow, and what would change
/// it. The experts' texts and the glossary stay behind two rows (the existing reading screen). A report without a `short` block shows the
/// existing reading screen directly.
struct PFDailyReport529: View {
    let date: String

    @StateObject private var store: PFDocStore529<PFDailyShort.Document>

    init(date: String) {
        self.date = date
        _store = StateObject(wrappedValue: PFDocStore529<PFDailyShort.Document>(path: PFDocPath529.dailyReport(date),
                                                                                  isEmpty: { $0.short == nil }))
    }

    var body: some View {
        Group {
            switch store.state {
            case .loading:
                PFDocPlaceholder529(kind: .loading).planScreen529(title: "Daily report", identifier: "plan529-daily-report")
            case .failed:
                PFDocPlaceholder529(kind: .failed, retry: { Task { await store.refresh() } })
                    .planScreen529(title: "Daily report", identifier: "plan529-daily-report")
            case .empty:
                PFReportsScreen(kind: .daily)
            case .loaded(let doc):
                PFDailyShortView529(short: doc.short ?? PFDailyShort())
                    .planScreen529(title: doc.short?.title ?? "Daily report", identifier: "plan529-daily-report")
            }
        }
        .task { await store.refreshIfStale() }
    }
}

struct PFDailyShortView529: View {
    let short: PFDailyShort

    @State private var showsWords = false
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if let verdict = short.verdict {
                    Text(hiding.text(verdict))
                        .font(LookFont.text(22, weight: .bold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("daily-verdict")
                }
                if let cause = short.cause {
                    Text(hiding.text(cause))
                        .font(LookFont.text(14.5))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .planCard529()
            if let devices = short.devices, !devices.isEmpty { devicesCard(devices) }
            if let blocks = short.blocks, !blocks.isEmpty { blocksCard(blocks) }
            linksCard
        }
        .sheet(isPresented: $showsWords) { PFGlossarySheet529() }
    }

    /// Each device on its own: the name leads, never one merged number.
    private func devicesCard(_ devices: [PFDailyShort.Device]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PFOver529(text: short.devicesTitle ?? "This morning, each device on its own")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(devices.enumerated()), id: \.offset) { _, device in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.source ?? "")
                            .font(LookFont.text(11, weight: .semibold))
                            .foregroundStyle(NoopLook.textTertiary)
                        Text(hiding.shown(device.value ?? "\u{2013}", .scores))
                            .font(LookFont.numeral(20))
                            .foregroundStyle(NoopLook.textPrimary)
                        if let label = device.label {
                            Text(hiding.text(label))
                                .font(LookFont.text(11.5))
                                .foregroundStyle(NoopLook.textTertiary)
                        }
                        ForEach(Array((device.lines ?? []).enumerated()), id: \.offset) { _, line in
                            Text(hiding.text(line))
                                .font(LookFont.text(11.5))
                                .foregroundStyle(NoopLook.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NoopLook.row))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("daily-device-\(device.source ?? "")")
                }
            }
            if let note = short.devicesNote {
                Text(hiding.text(note))
                    .font(LookFont.text(12.5))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .planCard529()
        .containerIdentifier("daily-devices")
    }

    private func blocksCard(_ blocks: [PFDailyShort.Block]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                VStack(alignment: .leading, spacing: 2) {
                    PFOver529(text: block.title ?? "")
                    Text(hiding.text(block.text ?? ""))
                        .font(LookFont.text(14.5))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .planCard529()
        .containerIdentifier("daily-blocks")
    }

    private var linksCard: some View {
        VStack(spacing: 0) {
            NavigationLink(value: TabRoute.reports("daily")) {
                PFRow529(title: "What each expert read", sub: "Sleep, health, nutrition, physio, running, mind", showsChevron: true)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("daily-experts")
            PFDivider529()
            Button { showsWords = true } label: {
                PFRow529(title: "Words used here", showsChevron: true).padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("daily-words")
        }
        .planCard529(padding: 0)
    }
}

/// "Words used here": the glossary of the latest daily reading (the one the reading screen folds as Glossary).
struct PFGlossarySheet529: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reports = PFReportsStore.shared

    private var entries: [PFReportGlossaryEntry] {
        guard let key = reports.rows[.daily]?.first?.key else { return [] }
        return reports.reports[PFReportsStore.reportID(.daily, key)]?.glossary ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if entries.isEmpty {
                        Text("No special words in this report.")
                            .font(LookFont.text(14))
                            .foregroundStyle(NoopLook.textSecondary)
                            .planCard529()
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.term)
                                        .font(LookFont.text(15, weight: .semibold))
                                        .foregroundStyle(NoopLook.textPrimary)
                                    Text(entry.text)
                                        .font(LookFont.text(13.5))
                                        .foregroundStyle(NoopLook.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .planCard529()
                    }
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
            }
            .lookScreenBackground()
            .navigationTitle("Words used here")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .containerIdentifier("daily-glossary-sheet")
        .task {
            await reports.loadIndex()
            if let key = reports.rows[.daily]?.first?.key { await reports.loadReport(.daily, key: key) }
        }
    }
}
