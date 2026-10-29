import SwiftUI
import PhotosUI
import StrandDesign

// What a finished session's results sheet lets the athlete add afterwards: how hard it felt (any time, a 1-10 row) and a photo of
// the workout. Both go through the job door (PaceForgeJob.swift). Small and plain on purpose: one tap for the effort, and a photo
// that is only a rough idea for the assessment, so nothing is asked of the athlete once it is sent.

/// The two cards under a results sheet's other cards. One view, so the sheet's own column gains a single child.
struct PFResultsRating: View {
    let workout: PFWorkout
    /// The rating PaceForge already holds for this session.
    let rpe: Double?
    /// PaceForge's saved one-line reading of this session's photo, when there is one.
    let photoSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PFRpeCard(workout: workout, saved: rpe)
            PFWorkoutPhotoCard(workout: workout, savedSummary: photoSummary)
        }
    }
}

// MARK: How hard it felt

/// "How hard it felt" once there is a rating; before that, one row of 1-10 chips that saves it (`save-rpe`, any session at any time).
private struct PFRpeCard: View {
    let workout: PFWorkout
    let saved: Double?

    @EnvironmentObject private var model: PFModel
    @StateObject private var tracker = PFJobTracker()
    @State private var justSaved: Int?

    private var shown: Double? { saved ?? justSaved.map { Double($0) } }
    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        if let shown {
            ratedCard(shown)
        } else if PFJobInputs.activityID(workout.activityId) != nil {
            PFCard(String(localized: "How hard did it feel?"), icon: "gauge.with.dots.needle.67percent") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tap a number. 1 is very easy, 10 is all out.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        ForEach(1...10, id: \.self) { value in chip(value) }
                    }
                    status
                }
            }
            .containerIdentifier("pf-rpe-input")
        }
    }

    private func ratedCard(_ rpe: Double) -> some View {
        PFCard("How hard it felt", icon: "gauge.with.dots.needle.67percent") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(PFFormat.trimmed(rpe))
                    .font(StrandFont.rounded(30))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("RPE of 10").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                if let target = workout.targetRpe {
                    Spacer(minLength: 8)
                    Text("planned \(PFFormat.trimmed(target))")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    private func chip(_ value: Int) -> some View {
        Button {
            Task { await save(value) }
        } label: {
            Text(String(value))
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceInset))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityIdentifier("pf-rpe-\(value)")
    }

    @ViewBuilder private var status: some View {
        switch tracker.phase {
        case .sending, .working:
            Text("Saving")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        case .failed(let message):
            Text(message)
                .font(StrandFont.caption)
                .foregroundStyle(PFColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        case .idle, .done:
            EmptyView()
        }
    }

    @MainActor private func save(_ value: Int) async {
        guard let inputs = PFJobInputs.saveRpe(value, activityID: workout.activityId, date: workout.date) else { return }
        if case .success = await tracker.run(.saveRpe, inputs: inputs) {
            justSaved = value
            await model.refresh()
        }
    }
}

// MARK: Workout photo

/// "Add workout photo": the library picker, then the photo goes to PaceForge, which reads it. No review step and no required field.
private struct PFWorkoutPhotoCard: View {
    let workout: PFWorkout
    let savedSummary: String?

    @StateObject private var flow = PFPhotoFlow()
    @State private var pickerItem: PhotosPickerItem?
    private let hiding = PFHiding()

    var body: some View {
        PFCard(String(localized: "Workout photo"), icon: "photo") {
            VStack(alignment: .leading, spacing: 10) {
                if let savedSummary, !showsFreshReading {
                    Text("Workout from your photo: \(hiding.text(savedSummary))")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pf-photo-saved")
                }
                stageLine
                if !flow.isBusy { picker }
            }
        }
        .containerIdentifier("pf-workout-photo")
        .task { await flow.checkEarlier(activityID: workout.activityId, date: workout.date) }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task { await upload(item) }
        }
    }

    /// An item that cannot be loaded goes on as empty data, which the flow reports as a photo that could not be opened.
    @MainActor private func upload(_ item: PhotosPickerItem) async {
        let data = (try? await item.loadTransferable(type: Data.self)) ?? Data()
        await flow.upload(data, activityID: workout.activityId, date: workout.date)
    }

    private var showsFreshReading: Bool {
        if case .read = flow.stage { return true }
        return false
    }

    private var picker: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Label("Add workout photo", systemImage: "photo.badge.plus")
                .font(StrandFont.subhead.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(StrandPalette.accent)
        .accessibilityIdentifier("pf-photo-add")
    }

    @ViewBuilder private var stageLine: some View {
        switch flow.stage {
        case .idle:
            Text("A rough idea is enough. PaceForge reads the photo; you do not need to check it.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        case .sending:
            progress("Sending your photo")
        case .reading:
            progress("Reading your photo")
        case .read(let summary):
            readLine(summary)
        case .retrying:
            note("PaceForge could not read it yet. It will keep trying on its own.", color: StrandPalette.textSecondary)
        case .couldNotRead:
            note("PaceForge could not read this photo. You can try another.", color: PFColor.warning)
        case .failed(let message):
            Text(message)
                .font(StrandFont.caption)
                .foregroundStyle(PFColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func progress(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private func note(_ text: LocalizedStringKey, color: Color) -> some View {
        Text(text)
            .font(StrandFont.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func readLine(_ summary: String?) -> some View {
        if let summary {
            Text("Workout from your photo: \(hiding.text(summary))")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pf-photo-read")
        } else {
            Text("Photo read.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
        }
    }
}
