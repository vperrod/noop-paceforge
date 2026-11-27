import SwiftUI
import PhotosUI
import UIKit
import StrandDesign
import WhoopStore

// The share cards (Day, Workout, Streak): what each one says, its drawing, the editor sheet (plain card or the
// athlete's photo) and the image handed to the iOS share sheet. Every value is printed by the formatter of the screen
// the Share button sits on. The cards are dark in both appearances.

// MARK: - What a card says

struct ShareCardModel: Identifiable {
    struct Ring {
        var score: Double
        var text: String
        var average: String?
    }

    struct Stat: Identifiable {
        var label: String
        var value: String
        var average: String?
        var color: Color = .white
        var id: String { label }
    }

    enum Content {
        case day(ring: Ring?, stats: [Stat])
        case workout(activity: String, duration: String?, stats: [Stat])
        case streak(count: Int)
    }

    let id = UUID()
    /// Top right of the card: the date, or "Streak".
    var heading: String
    var content: Content
    var source: String?

    @MainActor static func day(_ figures: ShareDayFigures, dayKey: String, effortScale: EffortScale) -> ShareCardModel {
        func stat(_ label: String, _ figure: ShareFigure?, color: Color = .white, text: (Double) -> String) -> Stat? {
            figure.map { Stat(label: label, value: text($0.value), average: $0.average.map { "avg \(text($0))" }, color: color) }
        }
        // The Today dials' own text: Charge whole, Effort on the chosen scale. Sleep, HRV and resting HR as Today prints them.
        let charge: (Double) -> String = { SixRingNoopInput.valueText($0, decimals: 0) + "%" }
        let effort: (Double) -> String = {
            SixRingNoopInput.valueText(UnitFormatter.effortValue($0, scale: effortScale), decimals: effortScale == .whoop ? 1 : 0)
        }
        let whole: (Double) -> String = { String(Int($0.rounded())) }
        let ring = figures.charge.map {
            Ring(score: $0.value, text: SixRingNoopInput.valueText($0.value, decimals: 0),
                 average: $0.average.map { "30-day average \(charge($0))" })
        }
        let stats = [
            stat("Sleep", figures.sleepMin, color: NoopLook.rest, text: LiquidTodayView.sleepDurationText),
            stat("Effort", figures.effort, color: NoopLook.effort, text: effort),
            stat("HRV ms", figures.hrv, text: whole),
            stat("Resting HR", figures.restingHr, text: whole),
        ].compactMap { $0 }
        return ShareCardModel(heading: PFDocDate.dayMonthYear(dayKey) ?? dayKey, content: .day(ring: ring, stats: stats),
                              source: figures.sourceLine)
    }

    @MainActor static func workout(_ row: WorkoutRow, effortScale: EffortScale, distanceSystem: UnitSystem) -> ShareCardModel {
        let figures = ShareWorkoutFigures(durationS: row.durationS, avgHr: row.avgHr, maxHr: row.maxHr, kcal: row.energyKcal,
                                          distanceM: row.distanceM, effort: row.strain)
        let readings: [Stat?] = [
            figures.avgHr.map { Stat(label: "Avg HR", value: "\($0)") },
            figures.maxHr.map { Stat(label: "Max HR", value: "\($0)") },
            figures.kcal.map { Stat(label: "Kcal", value: WorkoutDetailView.grouped($0)) },
            figures.distanceM.map { Stat(label: "Distance", value: UnitFormatter.distanceFromMeters($0, system: distanceSystem)) },
            figures.effort.map {
                Stat(label: "Effort", value: UnitFormatter.effortDisplay($0, scale: effortScale), color: NoopLook.effort)
            },
        ]
        let stats = readings.compactMap { $0 }
        let dayKey = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(row.startTs)))
        return ShareCardModel(heading: PFDocDate.dayMonthYear(dayKey) ?? dayKey,
                              content: .workout(activity: WorkoutSource.displaySport(row.sport),
                                                duration: figures.durationS.map { WorkoutDetailView.durationText($0) },
                                                stats: stats),
                              source: workoutSourceLine(row.source))
    }

    /// The streak Highlights leads with (the same count as the chip on Today).
    static func streak(_ streak: PFStreak) -> ShareCardModel {
        ShareCardModel(heading: "Streak", content: .streak(count: streak.current),
                       source: streak.source.map { "\($0) data" })
    }

    private static func workoutSourceLine(_ source: String) -> String {
        switch WorkoutSource.classify(source) {
        case .paceforge: return "PaceForge log"
        case .whoop: return "WHOOP data"
        case .apple: return WorkoutSource.isAppleHealth(source) ? "Apple Health data" : "Imported workout"
        case .detected: return "Detected by NOOP"
        case .manual: return "Manual log"
        case .lifting: return "Lifting import"
        case .activityFile: return "Activity file"
        }
    }
}

extension ShareDayValues {
    init(metric: DailyMetric) {
        self.init(day: metric.day, charge: metric.recovery, sleepMin: metric.totalSleepMin, effort: metric.strain,
                  hrv: metric.avgHrv, restingHr: metric.restingHr.map(Double.init))
    }
}

extension Repository {
    /// The stored rows behind the strap days from `from` to `to`, each named after the device that measured it, in the
    /// order the merge prefers them (imported before computed, the active device first).
    func shareStrapRows(from: String, to: String) async -> [ShareStrapRow] {
        guard let store = await storeHandle() else { return [] }
        let devices = (try? DeviceRegistryStore(dbQueue: store.registryWriter).all()) ?? []
        func name(_ id: String) -> String {
            TodayView.todayScoreProviderLabel(sourceId: id, brand: devices.first { $0.id == id }?.brand)
        }
        var out: [ShareStrapRow] = []
        for id in importedReadIds {
            for row in (try? await store.dailyMetrics(deviceId: id, from: from, to: to)) ?? [] {
                out.append(ShareStrapRow(values: ShareDayValues(metric: row), provider: name(id)))
            }
        }
        // A computed row's namespace does not say which device was worn: the score's stored input source does. A row
        // from before that was stored is WHOOP's only while no other brand has ever been paired; otherwise it has no name.
        let isOnlyWhoop = ShareStrapRow.isOnlyWhoop(brands: devices.map(\.brand))
        for id in computedReadIds {
            for row in (try? await store.dailyMetrics(deviceId: id, from: from, to: to)) ?? [] {
                var input: String?
                for key in ["recovery", "strain", "sleep_performance"] where input == nil {
                    input = (try? await store.scoreInputSource(deviceId: id, day: row.day, key: key)) ?? nil
                }
                guard let provider = input.map(name) ?? (isOnlyWhoop ? name(Repository.whoopSource) : nil) else { continue }
                out.append(ShareStrapRow(values: ShareDayValues(metric: row), provider: provider))
            }
        }
        return out
    }
}

// MARK: - The card

struct ShareCardView: View {
    static let size = CGSize(width: 320, height: 540)

    let model: ShareCardModel
    var photo: UIImage?

    private static let secondary = Color(hex: "#B0B5BA")

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: "NOOP")
                    .font(LookFont.numeral(20))
                    .tracking(4)
                    .foregroundStyle(.white)
                Spacer()
                Text(model.heading)
                    .font(LookFont.text(14))
                    .foregroundStyle(Self.secondary)
            }
            content
            Spacer(minLength: 0)
            if let source = model.source {
                Text(source)
                    .font(LookFont.text(11))
                    .foregroundStyle(Self.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .frame(width: Self.size.width, height: Self.size.height)
        .background { backdrop }
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var backdrop: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: Self.size.width, height: Self.size.height)
                .clipped()
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                }
        } else {
            LinearGradient(colors: [Color(hex: NoopLook.Hex.surface), Color(hex: NoopLook.Hex.bgStd)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.content {
        case .day(let ring, let stats):
            if let ring {
                RingDial(fraction: LookDial.fraction(ring.score, max: 100), color: NoopLook.chargeColor(ring.score),
                         valueText: ring.text, unitText: "%", diameter: 190, style: .hero, titleLines: ["Charge"],
                         accessibilityName: "Charge")
                    .padding(.top, 20)
                if let average = ring.average { caption(average).padding(.top, 8) }
            }
            grid(stats, columns: 2).padding(.top, 18)
        case .workout(let activity, let duration, let stats):
            Text(activity)
                .lookCaps(18)
                .foregroundStyle(.white)
                .padding(.top, 44)
            if let duration {
                bigNumber(duration, size: 80).padding(.top, 8)
                caption("DURATION")
            }
            grid(stats, columns: 3).padding(.top, 40)
        case .streak(let count):
            bigNumber("\(count)", size: 150).padding(.top, 90)
            caption("DAY STREAK")
        }
    }

    private func bigNumber(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(LookFont.numeral(size))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(LookFont.text(13))
            .foregroundStyle(Self.secondary)
    }

    // Plain stacks, not a lazy grid: ImageRenderer draws them whole, and a short last row stays centred.
    private func grid(_ stats: [ShareCardModel.Stat], columns: Int) -> some View {
        VStack(spacing: 14) {
            ForEach(Array(stride(from: 0, to: stats.count, by: columns)), id: \.self) { start in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(stats[start..<min(start + columns, stats.count)]) { stat in
                        VStack(spacing: 1) {
                            Text(stat.value)
                                .font(LookFont.numeral(30))
                                .foregroundStyle(stat.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(stat.label)
                                .lookCaps(11)
                                .foregroundStyle(.white)
                            if let average = stat.average {
                                Text(average)
                                    .font(LookFont.text(12))
                                    .foregroundStyle(Self.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - The image

@MainActor
enum ShareCardRenderer {
    /// Image pixels per card point.
    static let scale: CGFloat = 3
    static var pixelSize: CGSize { CGSize(width: ShareCardView.size.width * scale, height: ShareCardView.size.height * scale) }

    /// The card as an opaque 960 x 1620 image.
    static func image(_ model: ShareCardModel, photo: UIImage?) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(model: model, photo: photo).environment(\.colorScheme, .dark))
        renderer.scale = scale
        renderer.isOpaque = true
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent { image = renderer.uiImage }
        return image
    }
}

// MARK: - The editor sheet

struct ShareCardEditor: View {
    let model: ShareCardModel

    @Environment(\.dismiss) private var dismiss
    @State private var photo: UIImage?
    @State private var isShowingPhoto = false
    @State private var isPickerOpen = false
    @State private var pickerItem: PhotosPickerItem?
    /// Why the last pick shows no photo.
    @State private var photoProblem: String?

    private var shownPhoto: UIImage? { isShowingPhoto ? photo : nil }

    var body: some View {
        VStack(spacing: 14) {
            topBar
            GeometryReader { space in
                let scale = min(space.size.width / ShareCardView.size.width, space.size.height / ShareCardView.size.height, 1)
                ShareCardView(model: model, photo: shownPhoto)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .scaleEffect(scale)
                    .frame(width: space.size.width, height: space.size.height)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("share-card-preview")
            }
            if let photoProblem {
                Text(photoProblem)
                    .font(LookFont.text(13))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("share-editor-photo-problem")
            }
            HStack(spacing: 8) {
                chip("Card", isOn: !isShowingPhoto, id: "share-editor-card") {
                    isShowingPhoto = false
                    photoProblem = nil
                }
                // With no photo yet this opens Apple's picker; the card stays until a photo is chosen.
                chip("Photo", isOn: isShowingPhoto, id: "share-editor-photo") {
                    if photo == nil { isPickerOpen = true } else { isShowingPhoto = true }
                }
                if isShowingPhoto {
                    chip("Change photo", isOn: false, id: "share-editor-change") { isPickerOpen = true }
                }
            }
            Button {
                if let image = ShareCardRenderer.image(model, photo: shownPhoto) { FileExport.shareImage(image) }
            } label: {
                Text("Share")
                    .font(LookFont.text(17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("share-editor-share")
        }
        .padding(16)
        .background(Color(hex: NoopLook.Hex.bgAlt).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .photosPicker(isPresented: $isPickerOpen, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
    }

    private var topBar: some View {
        ZStack {
            Text("Share")
                .font(LookFont.text(17, weight: .semibold))
                .foregroundStyle(.white)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("share-editor-close")
                Spacer()
            }
        }
    }

    private func chip(_ title: String, isOn: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(LookFont.text(14, weight: .medium))
                .foregroundStyle(isOn ? .black : .white)
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
                .background(Capsule().fill(isOn ? Color.white : Color.clear))
                .overlay(Capsule().strokeBorder(Color(hex: NoopLook.Hex.borderHighlight)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    @MainActor private func load(_ item: PhotosPickerItem) async {
        photoProblem = nil
        let data = try? await item.loadTransferable(type: Data.self)
        // Cleared so that picking the same picture again is seen as a new pick.
        pickerItem = nil
        let target = ShareCardRenderer.pixelSize
        let picked = await Task.detached(priority: .userInitiated) {
            data.flatMap { SharePhoto.downscaled($0, covering: target) }
        }.value
        guard let picked else {
            isShowingPhoto = false
            photoProblem = "That photo couldn't be read."
            return
        }
        photo = UIImage(cgImage: picked)
        isShowingPhoto = true
    }
}

// MARK: - The toolbar button (workout detail, Highlights)

private struct ShareCardToolbar: ViewModifier {
    let identifier: String
    /// nil: there is nothing to make a card from, so there is no button.
    let makeCard: (@MainActor () -> ShareCardModel)?
    @State private var card: ShareCardModel?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let makeCard {
                        Button { card = makeCard() } label: { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("Share")
                            .accessibilityIdentifier(identifier)
                    }
                }
            }
            .sheet(item: $card) { ShareCardEditor(model: $0) }
    }
}

extension View {
    func shareCardToolbar(_ identifier: String, makeCard: (@MainActor () -> ShareCardModel)?) -> some View {
        modifier(ShareCardToolbar(identifier: identifier, makeCard: makeCard))
    }
}

// MARK: - Simulator harness

#if DEBUG
/// `--demo-screen sharecards` (ShareCardsUITests): writes the images the Share button would hand over, made from
/// made-up figures, into the folder the test names in SHARE_CARDS_DIR.
struct ShareCardRenderHarness: View {
    @State private var status = "Rendering"

    var body: some View {
        Text(status)
            .task { status = write() }
    }

    nonisolated static var fixtureWorkout: WorkoutRow {
        let start = Int(PFDocDate.date("2030-03-13")?.timeIntervalSince1970 ?? 0)
        return WorkoutRow(startTs: start, endTs: start + 1111, sport: "Fixture Run", source: "paceforge", durationS: 1111,
                          energyKcal: 222, avgHr: 111, maxHr: 144, strain: 33, distanceM: 3333, zonesJSON: nil, notes: nil,
                          steps: nil)
    }

    private var fixtureDay: ShareCardModel {
        let shown = ShareDayValues(day: "2030-03-13", charge: 77, sleepMin: 427, effort: 55, hrv: 66, restingHr: 44)
        let earlier = ["2030-03-10", "2030-03-11", "2030-03-12"].map {
            ShareDayValues(day: $0, charge: 55, sleepMin: 404, effort: 44, hrv: 55, restingHr: 46)
        }
        let figures = ShareDayFigures.make(shown: shown, history: earlier,
                                           rows: (earlier + [shown]).map { ShareStrapRow(values: $0, provider: "WHOOP") },
                                           strapLiveEffort: nil, liveProvider: "WHOOP", hidesScores: false,
                                           calendar: .current)
        return .day(figures, dayKey: shown.day, effortScale: .hundred)
    }

    private var fixturePhoto: UIImage {
        let size = CGSize(width: 600, height: 400)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemOrange.setFill()
            for x in stride(from: 0, to: size.width, by: 80) {
                context.fill(CGRect(x: x, y: 0, width: 40, height: size.height))
            }
        }
    }

    @MainActor private func write() -> String {
        guard let folder = ProcessInfo.processInfo.environment["SHARE_CARDS_DIR"] else { return "No folder" }
        let streak = PFStreak(id: "fixture", label: "Fixture streak", source: "NOOP", unit: "days", rule: nil, current: 7,
                              best: 7, since: nil, alive: true, line: nil)
        let cards: [(String, ShareCardModel, UIImage?)] = [
            ("day", fixtureDay, nil),
            ("workout", .workout(Self.fixtureWorkout, effortScale: .hundred, distanceSystem: .metric), nil),
            ("streak", .streak(streak), nil),
            ("day-photo", fixtureDay, fixturePhoto),
        ]
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            for (name, model, photo) in cards {
                guard let data = ShareCardRenderer.image(model, photo: photo)?.pngData() else { return "No image: \(name)" }
                try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
            }
        } catch {
            return "Write failed: \(error)"
        }
        return "Rendered"
    }
}
#endif
