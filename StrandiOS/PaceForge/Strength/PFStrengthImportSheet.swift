import SwiftUI
import UniformTypeIdentifiers
import StrandDesign

// Import a strength CSV from the Lift Log area: pick the file, PaceForge reads it and says what saving it would do (mapped exercises,
// units, duplicates, rejected rows with the reason), and nothing is saved until the athlete confirms that preview. The inputs and how the
// preview reads are in PaceForgeStrength.swift (unit-tested). A summary file (Strava, Garmin) is shown as summaries and never as sets.

struct PFStrengthImportSheet: View {
    /// Called after a confirmed import has saved, so the history under the Lift Log reads again.
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var tracker = PFJobTracker()
    @State private var provider = PFStrengthProvider.hevy
    @State private var picking = false
    @State private var fileName: String?
    @State private var content: String?
    @State private var preview: PFStrengthPreview?
    @State private var saved: PFStrengthImportResult?
    @State private var message: String?
    @State private var showsAllItems = false
    @State private var showsRows = false

    /// A file this big cannot be 400 000 characters; checked before the file is read into memory.
    private static let maxBytes = 1_700_000
    private static let itemsShown = 30
    private static let rowsShown = 20

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    chooser
                    if isBusy { working }
                    if let message { notice(message) }
                    if let saved { savedCard(saved) } else if let preview { previewCards(preview) }
                }
                .padding(.horizontal, NoopMetrics.gap)
                .padding(.vertical, NoopMetrics.gap)
            }
            .navigationTitle("Import strength")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(saved == nil ? "Cancel" : "Done") { dismiss() }
                        .accessibilityIdentifier("strength-import-close")
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .data],
                          allowsMultipleSelection: false) { result in
                handle(result)
            }
        }
        .containerIdentifier("strength-import-sheet")
    }

    // MARK: Choose

    private var chooser: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("What kind of file is it?")
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Picker("File kind", selection: $provider) {
                    ForEach(PFStrengthProvider.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(isBusy || saved != nil)
                .accessibilityIdentifier("strength-import-provider")
                .onChange(of: provider) { _, _ in
                    // The same file read as another kind is a different preview.
                    if content != nil { Task { await runPreview() } }
                }
                Text(provider.hint)
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    picking = true
                } label: {
                    Label(fileName == nil ? "Choose a CSV file" : "Choose another file", systemImage: "doc.badge.plus")
                }
                .buttonStyle(NoopButtonStyle(.secondary))
                .disabled(isBusy)
                .accessibilityIdentifier("strength-import-choose")
                if let fileName {
                    Text(fileName).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).lineLimit(1)
                }
            }
        }
    }

    private var working: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(preview == nil ? "Reading the file" : "Saving").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(StrandFont.subhead).foregroundStyle(PFColor.warning)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("strength-import-message")
    }

    // MARK: Preview

    @ViewBuilder private func previewCards(_ preview: PFStrengthPreview) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(preview.isSummary ? "Session summaries" : "Workouts with sets")
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                if let nothing = preview.nothingToSave {
                    Text(nothing).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
                ForEach(preview.countLines, id: \.self) { line in
                    Text(line).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                }
                if !preview.isSummary, preview.kgCount + preview.lbCount > 0 {
                    Text(unitsLine(preview)).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                }
                if let note = preview.note {
                    Text(note).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let blocked = preview.blocked {
                    Text(blocked + ". Nothing can be saved from this file.")
                        .font(StrandFont.subhead).foregroundStyle(PFColor.warning)
                }
            }
        }
        .accessibilityIdentifier("strength-import-counts")
        if !preview.mapping.isEmpty { mappingCard(preview) }
        if !preview.items.isEmpty { itemsCard(preview) }
        if preview.counts.rejected > 0 { rejectedCard(preview) }
        if !preview.skipped.isEmpty { skippedCard(preview) }
        Button {
            Task { await confirm(preview) }
        } label: {
            Text(preview.confirmTitle).frame(maxWidth: .infinity)
        }
        .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
        .disabled(!preview.canConfirm || isBusy)
        .accessibilityIdentifier("strength-import-confirm")
        Text("Nothing is saved until you press this. Importing the same file again saves nothing new.")
            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func unitsLine(_ preview: PFStrengthPreview) -> String {
        var parts: [String] = []
        if preview.kgCount > 0 { parts.append("\(preview.kgCount) in kg") }
        if preview.lbCount > 0 { parts.append("\(preview.lbCount) in lb, converted to kg") }
        return "Weights: " + parts.joined(separator: ", ") + "."
    }

    private func mappingCard(_ preview: PFStrengthPreview) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Exercises in the file").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                ForEach(preview.mapping) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.providerName).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                        Text(row.isMapped ? "Placed on \(row.name ?? "a library exercise") \u{00B7} \(row.rows) rows"
                             : "Not matched to a library exercise, so its \(row.rows) rows are rejected")
                            .font(StrandFont.caption)
                            .foregroundStyle(row.isMapped ? StrandPalette.textSecondary : PFColor.warning)
                    }
                }
                if !preview.unmapped.isEmpty {
                    Text("Names are matched exactly, by the words in them. Rename the exercise in the file to match, then choose it again.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("strength-import-mapping")
    }

    private func itemsCard(_ preview: PFStrengthPreview) -> some View {
        let shown = showsAllItems ? preview.items : Array(preview.items.prefix(Self.itemsShown))
        return NoopCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(preview.isSummary ? "Summaries in the file" : "Workouts in the file")
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                ForEach(shown) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(PFStrengthHistory.heading(date: item.date, title: item.title))
                                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                            Spacer(minLength: 6)
                            Text(PFStrengthPreview.statusLabel(item.status))
                                .font(StrandFont.caption)
                                .foregroundStyle(item.status == "new" ? PFColor.positive : StrandPalette.textTertiary)
                        }
                        Text(itemDetail(item, summary: preview.isSummary))
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let reason = item.reason, !reason.isEmpty {
                            Text(reason).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                }
                if preview.items.count > Self.itemsShown {
                    Button(showsAllItems ? "Show fewer" : "Show all \(preview.items.count)") { showsAllItems.toggle() }
                        .font(StrandFont.subhead)
                }
                if preview.counts.items > preview.items.count {
                    Text("The first \(preview.items.count) of \(preview.counts.items) are listed; the counts above are exact.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .accessibilityIdentifier("strength-import-items")
    }

    /// A workout: how many sets and which exercises. A summary: how long, and never a set count it does not have.
    private func itemDetail(_ item: PFStrengthPreview.Item, summary: Bool) -> String {
        if summary {
            return item.durationSeconds.map { PFStrengthHistory.durationText(seconds: $0) } ?? "Duration not given"
        }
        let sets = item.setCount.map { "\($0) \($0 == 1 ? "set" : "sets")" } ?? ""
        let exercises = item.exercises.joined(separator: ", ")
        return [sets, exercises].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    private func rejectedCard(_ preview: PFStrengthPreview) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Rejected rows").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                ForEach(preview.rejectedReasons) { reason in
                    Text("\(reason.count) \u{00D7} \(reason.text)").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                }
                let rows = showsRows ? preview.rejected : Array(preview.rejected.prefix(Self.rowsShown))
                ForEach(rows) { row in
                    Text("Row \(row.row): \(row.reason)").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                if preview.rejected.count > Self.rowsShown {
                    Button(showsRows ? "Show fewer rows" : "Show the first \(preview.rejected.count) rows") { showsRows.toggle() }
                        .font(StrandFont.subhead)
                }
                Text("Rejected rows are never saved or guessed. Row numbers do not count the header.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .accessibilityIdentifier("strength-import-rejected")
    }

    private func skippedCard(_ preview: PFStrengthPreview) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Skipped rows").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                ForEach(Array(preview.skipped.prefix(Self.rowsShown))) { row in
                    Text("Row \(row.row): \(row.reason)").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    private func savedCard(_ result: PFStrengthImportResult) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Import finished").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text(result.line).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if result.kind == "summary" {
                    Text("Summaries are kept as session summaries. They do not count toward bests.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .accessibilityIdentifier("strength-import-saved")
    }

    // MARK: Work

    private func handle(_ outcome: Result<[URL], Error>) {
        switch outcome {
        case .failure(let error):
            message = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard bytes <= Self.maxBytes else {
                message = PFStrengthImport.tooBig
                return
            }
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
                message = "That file could not be read as text."
                return
            }
            if let problem = PFStrengthImport.problem(with: text) {
                message = problem
                return
            }
            fileName = url.lastPathComponent
            content = text
            preview = nil
            saved = nil
            message = nil
            Task { await runPreview() }
        }
    }

    @MainActor private func runPreview() async {
        guard let content, let inputs = PFJobInputs.strengthImportPreview(provider: provider, content: content) else { return }
        message = nil
        preview = nil
        switch await tracker.run(.strengthImportPreview, inputs: inputs) {
        case .failure(let failure):
            message = failure.message
        case .success(let result):
            if let parsed = PFStrengthPreview.parse(result) {
                preview = parsed
                showsAllItems = false
                showsRows = false
            } else {
                message = PFJobError.unreadable.message
            }
        }
    }

    @MainActor private func confirm(_ shown: PFStrengthPreview) async {
        guard let content, let inputs = PFJobInputs.strengthImport(provider: provider, content: content, confirm: shown.previewID) else { return }
        message = nil
        switch await tracker.run(.strengthImport, inputs: inputs) {
        case .failure(let failure):
            // "The file or what is already saved changed since the preview": the preview is read again so the athlete confirms what is true now.
            message = failure.message
            if case .refused = failure { await runPreview(keepingMessage: failure.message) }
        case .success(let result):
            if let done = PFStrengthImportResult.parse(result) {
                saved = done
                preview = nil
                await onSaved()
            } else {
                message = PFJobError.unreadable.message
            }
        }
    }

    @MainActor private func runPreview(keepingMessage text: String) async {
        await runPreview()
        message = text
    }
}
