import SwiftUI
import StrandDesign
import WhoopStore

// What the two exercise pickers share: the program line editor (`LiftProgramItemSheet`) and the running
// session's Add exercise sheet (`LiftSessionExerciseSheet`). The user's own exercise names offered back,
// a name remembered with its muscles, and the muscle classification itself — one copy of each, so the two
// pickers cannot drift about what a name is or which muscles it works.

/// The user's own exercise names (`liftExercise`), as the pickers read and write them.
enum LiftExerciseVocabulary {

    /// Names matching what has been typed so far, minus an exact match (no point suggesting the thing
    /// already in the box), most recently used first as the store orders them. Capped — this is a hint,
    /// not a browser.
    static func suggestions(_ vocabulary: [LiftExerciseRow], matching typed: String,
                            limit: Int = 6, filter: LiftExerciseFilter = LiftExerciseFilter(),
                            equipmentOf: (String) -> LiftEquipment? = { LiftEquipmentStore.equipment(for: $0) }) -> [LiftExerciseRow] {
        // The muscle group and equipment filters narrow the list first. With one set, the list is a browser
        // for that group rather than a hint, so it is allowed to run longer.
        let pool = filter.apply(vocabulary, primary: { $0.primaryMuscle }, name: { $0.name }, equipmentOf: equipmentOf)
        let cap = filter.isActive ? max(limit, 12) : limit
        let query = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return Array(pool.prefix(cap)) }
        return Array(pool
            .filter { $0.name.lowercased().contains(query) && $0.name.lowercased() != query }
            .prefix(cap))
    }

    /// Remember `name` with its muscles, so it is offered back next time. `upsertLiftExercises` is keyed
    /// on (deviceId, name), so a known name is updated — its muscles, and when it was last used — never
    /// duplicated. Throws `WhoopStore.LiftExerciseVocabularyFull` for a NEW name once the vocabulary is
    /// full, which the caller explains rather than dropping the name silently.
    static func remember(_ name: String, primary: LiftMuscle?, secondaries: [LiftMuscle],
                         known vocabulary: [LiftExerciseRow], deviceId: String,
                         in store: WhoopStore) async throws {
        let now = Int(Date().timeIntervalSince1970)
        let existing = vocabulary.first { $0.name == name }
        _ = try await store.upsertLiftExercises([LiftExerciseRow(
            id: existing?.id ?? UUID().uuidString,
            deviceId: deviceId,
            name: name,
            primaryMuscle: primary,
            secondaryMuscles: secondaries,
            createdAt: existing?.createdAt ?? now,
            lastUsedTs: now)])
    }

    /// Secondaries in the vocabulary's canonical order rather than `Set` iteration order, so the stored
    /// list is stable between saves instead of reshuffling on every edit.
    static func ordered(_ secondaries: Set<LiftMuscle>, excluding primary: LiftMuscle?) -> [LiftMuscle] {
        LiftMuscle.ordered.filter { secondaries.contains($0) && $0 != primary }
    }
}

/// One remembered exercise as a picker lists it: its name, and the muscles it is known by.
struct LiftExerciseSuggestionLabel: View {
    let row: LiftExerciseRow
    /// The equipment tag kept for this exercise, shown beside its muscles.
    var equipment: LiftEquipment? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.left")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(LiftMuscleSummary.line(primary: row.primaryMuscle, secondaries: row.secondaryMuscles)
                     + (equipment.map { " \u{00B7} " + $0.displayName } ?? ""))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// The muscle classification: the primary muscle (a direct set) and the muscles an exercise also works
/// (half a set each). Asked once per exercise and remembered with its name; leaving it unset is allowed —
/// an unclassified exercise still counts toward volume and session load, it simply claims no muscle it
/// was never assigned.
struct LiftMusclePicker: View {
    @Binding var primary: LiftMuscle?
    @Binding var secondaries: Set<LiftMuscle>

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Muscles", overline: "Counted once per exercise")
            NoopCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Primary").strandOverline()
                        Menu {
                            Button("Not classified") { primary = nil }
                            ForEach(LiftMuscle.Region.allCases, id: \.self) { region in
                                Section(region.displayName) {
                                    ForEach(LiftMuscle.inRegion(region), id: \.self) { muscle in
                                        Button(muscle.displayName) { select(primary: muscle) }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(primary?.displayName ?? String(localized: "Not classified"))
                                    .font(StrandFont.body)
                                    .foregroundStyle(primary == nil
                                                     ? StrandPalette.textTertiary
                                                     : StrandPalette.textPrimary)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Primary muscle")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Also works (counted as half a set)").strandOverline()
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                                  alignment: .leading, spacing: 8) {
                            ForEach(LiftMuscle.allCases, id: \.self) { muscle in
                                if muscle != primary {
                                    secondaryChip(muscle)
                                }
                            }
                        }
                    }

                    Text("Direct sets count once, indirect sets count as a half. That split is what makes the weekly per-muscle figures mean anything.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func secondaryChip(_ muscle: LiftMuscle) -> some View {
        let on = secondaries.contains(muscle)
        return Button {
            if on { secondaries.remove(muscle) } else { secondaries.insert(muscle) }
        } label: {
            Text(muscle.displayName)
                .font(StrandFont.caption)
                .foregroundStyle(on ? StrandPalette.effortColor : StrandPalette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(on ? StrandPalette.effortColor.opacity(0.14) : StrandPalette.surfaceRaised)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// Setting a primary that is also ticked as a secondary drops it from the secondaries: one
    /// muscle can never be credited twice for the same set.
    private func select(primary muscle: LiftMuscle) {
        primary = muscle
        secondaries.remove(muscle)
    }
}

// MARK: - Filters and the equipment tag

/// Two rows of chips above the "Used before" list: a muscle group (push, pull, legs, trunk) and an equipment.
/// Tapping the chip that is already chosen clears it.
struct LiftExerciseFilterBar: View {
    @Binding var filter: LiftExerciseFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chips(title: "Muscle group", options: LiftMuscle.Region.allCases.map { ($0.filterName, $0) },
                  selection: $filter.region, identifier: "lift-filter-region")
            chips(title: "Equipment", options: LiftEquipment.allCases.map { ($0.displayName, $0) },
                  selection: $filter.equipment, identifier: "lift-filter-equipment")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lift-filter-bar")
    }

    private func chips<Value: Hashable>(title: String, options: [(String, Value)], selection: Binding<Value?>,
                                        identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title).strandOverline()
            LookFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        let on = selection.wrappedValue == option.1
                        Button {
                            selection.wrappedValue = on ? nil : option.1
                        } label: {
                            Text(verbatim: option.0)
                                .font(StrandFont.caption)
                                .foregroundStyle(on ? StrandPalette.effortColor : StrandPalette.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(on ? StrandPalette.effortColor.opacity(0.14) : StrandPalette.surfaceRaised)
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                        .accessibilityIdentifier("\(identifier)-\(option.0.lowercased())")
                    }
            }
        }
    }
}

/// The equipment an exercise uses, picked once and remembered with its name. Leaving it unset is allowed.
struct LiftEquipmentPicker: View {
    @Binding var equipment: LiftEquipment?

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Equipment", overline: "Optional")
            NoopCard {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(LiftEquipment.allCases) { item in
                            let on = equipment == item
                            Button { equipment = on ? nil : item } label: {
                                Text(verbatim: item.displayName)
                                    .font(StrandFont.caption)
                                    .foregroundStyle(on ? StrandPalette.effortColor : StrandPalette.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(on ? StrandPalette.effortColor.opacity(0.14) : StrandPalette.surfaceRaised)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? [.isSelected] : [])
                            .accessibilityIdentifier("lift-equipment-\(item.rawValue)")
                        }
                    }
                    Text(verbatim: "Kept on this iPhone beside the exercise name. The pickers use it to narrow their list.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
