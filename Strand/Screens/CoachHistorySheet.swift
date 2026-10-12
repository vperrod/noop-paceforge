import SwiftUI
import MarkdownUI
import StrandDesign

/// The conversations Coach has put away: a list (newest first) and a read-only view of each, with a button to
/// continue one. "New conversation" in the Coach header puts the current thread here; so does the day
/// rolling over. Everything is kept on this device only.
struct CoachHistorySheet: View {
    @EnvironmentObject var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss
    @State private var selected: CoachConversationRecord?

    var body: some View {
        NavigationStack {
            Group {
                if coach.history.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text(verbatim: "Conversation history"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text(verbatim: "Done") }
                        .accessibilityIdentifier("coach-history-done")
                }
            }
        }
        .sheet(item: $selected) { record in
            CoachConversationPreview(record: record) {
                coach.openConversation(record)
                selected = nil
                dismiss()
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-history-sheet")
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Text(verbatim: "No earlier conversations")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            Text(verbatim: "When you start a new conversation, or a new day begins, the last one is kept here.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("coach-history-empty")
    }

    private var list: some View {
        List {
            ForEach(coach.history) { record in
                Button { selected = record } label: { row(record) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach-history-row-\(record.id)")
            }
            .onDelete { offsets in
                let ids = offsets.map { coach.history[$0].id }
                for id in ids { coach.deleteConversation(id: id) }
            }
        }
        .listStyle(.plain)
    }

    private func row(_ record: CoachConversationRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: record.title)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(2)
            Text(verbatim: "\(record.archivedAt.formatted(date: .abbreviated, time: .shortened)) \u{00B7} \(record.messageCount) messages")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// One past conversation, read-only, with the button that makes it the current one.
struct CoachConversationPreview: View {
    let record: CoachConversationRecord
    let onContinue: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(record.messages.enumerated()), id: \.offset) { _, message in
                        if message.role == "user" {
                            Text(verbatim: message.text)
                                .font(StrandFont.body)
                                .foregroundStyle(StrandPalette.surfaceBase)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(StrandPalette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        } else {
                            Markdown(message.text)
                                .markdownTheme(.strand)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .frostedCardSurface(tint: StrandPalette.chargeColor, cornerRadius: 16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(16)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text(verbatim: record.title))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(verbatim: "Close") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { onContinue() } label: { Text(verbatim: "Continue") }
                        .accessibilityIdentifier("coach-history-continue")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }
}
