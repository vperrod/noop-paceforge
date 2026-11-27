import SwiftUI
import StrandDesign

// Awards inside Highlights, in the look of the streak badges: the current WHOOP Charge streak, one row per award, the steps of
// an award, the one-time celebration and the challenges you set yourself.

extension AwardKind {
    var symbol: String {
        switch self {
        case .chargeStreak: return "flame.fill"
        case .greenDays: return "bolt.heart.fill"
        case .sevenHourNights: return "moon.fill"
        case .hardDays: return "figure.strengthtraining.traditional"
        case .activities: return "figure.run"
        }
    }

    var color: Color {
        switch self {
        case .chargeStreak: return NoopLook.zones[3]
        case .greenDays: return NoopLook.chargeHigh
        case .sevenHourNights: return NoopLook.rest
        case .hardDays: return NoopLook.effort
        case .activities: return NoopLook.trendUp
        }
    }

    var sourceName: String { isWhoopOnly ? "WHOOP" : "All sources" }
}

// MARK: - The section in Highlights

struct AwardsSection: View {
    @ObservedObject private var store = AwardsStore.shared
    @EnvironmentObject private var repo: Repository

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let counts = store.counts {
                streakCard(counts.currentStreak)
                awardsCard(counts)
                challengesRow
            }
        }
        .containerIdentifier("awards-section")
        .task(id: repo.refreshSeq) { await store.refresh(repo: repo) }
    }

    private func streakCard(_ streak: Int) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    PFOver529(text: "Current streak")
                    PFSourceTag(source: "WHOOP")
                }
                Text("\(streak)")
                    .lookNumeral(56)
                    .foregroundStyle(NoopLook.textPrimary)
                    .accessibilityIdentifier("awards-streak-count")
                Text("day\(streak == 1 ? "" : "s") in a row with a Charge")
                    .font(PFPlanFont543.text(13.5))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            PFBadgeIcon(symbol: AwardKind.chargeStreak.symbol, color: AwardKind.chargeStreak.color, size: 72,
                        isDimmed: streak == 0)
        }
        .planCard529(padding: 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("awards-streak")
    }

    private func awardsCard(_ counts: AwardCounts) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PFOver529(text: "Awards")
                .padding(.bottom, 4)
            ForEach(Array(AwardKind.allCases.enumerated()), id: \.element) { index, kind in
                if index > 0 { PFDivider529() }
                let count = counts.totals[kind]
                NavigationLink {
                    AwardDetailScreen(kind: kind)
                } label: {
                    AwardRow(kind: kind, count: count)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("award-row-\(kind.rawValue)")
            }
        }
        .planCard529(padding: 16)
    }

    private var challengesRow: some View {
        let running = store.challenges.filter {
            $0.state(progress: $0.progress(days: store.days, activityDays: store.activityDays), today: store.today) == .running
        }.count
        return NavigationLink {
            AwardChallengesScreen()
        } label: {
            PFRow529(title: "Challenges", sub: running == 0 ? "None running" : "\(running) running", showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("awards-challenges")
        .planCard529()
    }
}

/// An award as a row: its badge (dimmed until the first step), the count and the next step, and the level.
private struct AwardRow: View {
    let kind: AwardKind
    let count: Int?

    private var level: Int? { count.flatMap { Awards.level($0, kind) } }

    private var line: String {
        guard let count else { return "Not counted" }
        guard let next = Awards.next(count, kind) else { return "\(count) \u{00B7} every step reached" }
        return "\(count) \u{00B7} next \(next)"
    }

    var body: some View {
        HStack(spacing: 12) {
            PFBadgeIcon(symbol: kind.symbol, color: kind.color, size: 42, isDimmed: level == nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(PFPlanFont543.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                Text(line)
                    .font(PFPlanFont543.text(12.5))
                    .foregroundStyle(NoopLook.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(level.map(String.init) ?? "\u{2013}")
                    .lookNumeral(26)
                    .foregroundStyle(level == nil ? NoopLook.textTertiary : NoopLook.textPrimary)
                Text("Level").lookCaps(9).foregroundStyle(NoopLook.textTertiary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NoopLook.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

// MARK: - One award

struct AwardDetailScreen: View {
    let kind: AwardKind
    @ObservedObject private var store = AwardsStore.shared

    private var count: Int? { store.counts?.totals[kind] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 8) {
                PFBadgeIcon(symbol: kind.symbol, color: kind.color, size: 96,
                            isDimmed: count.flatMap { Awards.level($0, kind) } == nil)
                Text(count.map(String.init) ?? "\u{2013}")
                    .lookNumeral(56)
                    .foregroundStyle(NoopLook.textPrimary)
                PFSourceTag(source: kind.sourceName)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("award-detail-count")
            levels
            Text(kind.definition)
                .font(PFPlanFont543.text(13.5))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .planScreen529(title: kind.title, identifier: "award-detail")
    }

    private var levels: some View {
        VStack(alignment: .leading, spacing: 0) {
            PFOver529(text: "Levels")
                .padding(.bottom, 4)
            ForEach(Array(kind.steps.enumerated()), id: \.element) { index, step in
                if index > 0 { PFDivider529() }
                stepRow(step)
            }
        }
        .planCard529(padding: 16)
    }

    private func stepRow(_ step: Int) -> some View {
        let earned = (count ?? 0) >= step
        let isNext = count.flatMap { Awards.next($0, kind) } == step
        let state = earned ? "Earned" : (isNext ? "\(step - (count ?? 0)) to go" : "\u{2013}")
        return HStack {
            Text("\(step)")
                .lookNumeral(26)
                .foregroundStyle(earned || isNext ? NoopLook.textPrimary : NoopLook.textTertiary)
            Spacer(minLength: 8)
            if earned {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(kind.color)
                    .accessibilityHidden(true)
            }
            Text(state)
                .font(PFPlanFont543.text(13.5, weight: earned || isNext ? .semibold : .regular))
                .foregroundStyle(earned ? NoopLook.textPrimary : NoopLook.textSecondary)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step): \(state)")
        .accessibilityIdentifier("award-step-\(step)")
    }
}

// MARK: - Celebration

/// Puts a newly reached step over whatever is on screen, one at a time.
struct AwardCelebrationModifier: ViewModifier {
    @ObservedObject private var store = AwardsStore.shared
    @EnvironmentObject private var repo: Repository

    func body(content: Content) -> some View {
        content
            .task(id: repo.refreshSeq) {
                // After the first paint, and once a burst of refreshes has settled.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await store.refresh(repo: repo)
            }
            .fullScreenCover(item: Binding(get: { store.celebrations.first }, set: { _ in })) { celebration in
                AwardCelebrationScreen(celebration: celebration) { store.dismissCelebration() }
            }
    }
}

struct AwardCelebrationScreen: View {
    let celebration: AwardCelebration
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                Spacer()
                PFBadgeIcon(symbol: celebration.kind.symbol, color: celebration.kind.color, size: 150)
                VStack(spacing: 4) {
                    Text("\(celebration.step)")
                        .lookNumeral(96)
                        .foregroundStyle(NoopLook.textPrimary)
                    // The number is above, so the words follow it without repeating it.
                    Text(celebration.kind.phrase(celebration.step).drop { $0.isNumber || $0 == " " })
                        .font(LookFont.text(24, weight: .bold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(celebration.kind.phrase(celebration.step))
                .accessibilityIdentifier("award-celebration-title")
                Text("A new level in \(celebration.kind.title). Shown once.")
                    .font(LookFont.text(15, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer()
                Button(action: onDone) { TimingPrimaryLabel(title: "Done") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("award-celebration-done")
            }
            .padding(24)
            if !reduceMotion { ConfettiBurst().ignoresSafeArea().allowsHitTesting(false) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lookScreenBackground()
        .interactiveDismissDisabled()
    }
}

/// One burst of confetti in the look's data colours: it falls for a few seconds and stops.
private struct ConfettiBurst: View {
    private static let colors = [NoopLook.chargeHigh, NoopLook.chargeMedium, NoopLook.effort, NoopLook.stageRem,
                                 NoopLook.trendUp, NoopLook.zones[3]]
    private static let pieces = 110
    private static let seconds = 4.0

    @State private var start = Date()
    @State private var isOver = false

    /// `-ConfettiStill` (DEBUG) holds the burst one moment in, so a UI test can picture it.
    private static let stillAt: Double? = {
        #if DEBUG
        if CommandLine.arguments.contains("-ConfettiStill") { return 1.1 }
        #endif
        return nil
    }()

    var body: some View {
        TimelineView(.animation(paused: isOver || Self.stillAt != nil)) { context in
            Canvas { canvas, size in
                let t = Self.stillAt ?? context.date.timeIntervalSince(start)
                guard t < Self.seconds else { return }
                for piece in 0..<Self.pieces {
                    // A fixed scatter per piece: the fractional part of a multiple of an irrational number.
                    func scatter(_ factor: Double) -> Double { (Double(piece + 1) * factor).truncatingRemainder(dividingBy: 1) }
                    let width = Double(size.width)
                    let height = Double(size.height)
                    let sway: Double = 24 * sin(t * (1.5 + 2 * scatter(0.7320508)) + Double(piece))
                    let x: Double = width * scatter(0.6180339887) + sway
                    let speed: Double = height * (0.22 + 0.28 * scatter(0.4142135))
                    let startY: Double = -height * 0.45 * scatter(0.2360679)
                    let y: Double = startY + speed * t + 60 * t * t
                    var shape = canvas
                    shape.translateBy(x: x, y: y)
                    shape.rotate(by: .radians(t * (2 + 6 * scatter(0.3166247)) + Double(piece)))
                    shape.opacity = min(1, (Self.seconds - t) / 1.2)
                    shape.fill(Path(CGRect(x: -3.5, y: -5.5, width: 7, height: 11)),
                               with: .color(Self.colors[piece % Self.colors.count]))
                }
            }
        }
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(nanoseconds: UInt64(Self.seconds * 1_000_000_000))
            isOver = true
        }
    }
}

// MARK: - Challenges

struct AwardChallengesScreen: View {
    @ObservedObject private var store = AwardsStore.shared
    @State private var kind: AwardKind?
    @State private var targetText = ""
    @State private var endDay: String?
    @State private var isPickingDay = false
    @FocusState private var isTyping: Bool

    private var target: Int? { Int(targetText).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            newCard
            startButton
            list
        }
        .planScreen529(title: "Challenges", identifier: "award-challenges")
        .sheet(isPresented: $isPickingDay) {
            TimingDaySheet(title: "By", initial: endDay ?? store.today, earliest: store.today) { day in
                endDay = day
                isPickingDay = false
            }
        }
    }

    private var newCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            PFOver529(text: "New challenge")
            LookSegmented(options: AwardKind.challengeKinds.map { Optional($0) }, selection: $kind,
                          identifier: "challenge-kind") { $0?.title ?? "" }
            HStack {
                Text("How many")
                    .font(PFPlanFont543.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                Spacer(minLength: 8)
                TextField("How many", text: $targetText,
                          prompt: Text("you choose").font(PFPlanFont543.text(13.5)).foregroundColor(NoopLook.textSecondary))
                    .keyboardType(.numberPad)
                    .focused($isTyping)
                    .multilineTextAlignment(.trailing)
                    .lookNumeral(24)
                    .foregroundStyle(NoopLook.textPrimary)
                    .frame(maxWidth: 160)
                    .accessibilityIdentifier("challenge-target")
            }
            .frame(minHeight: 44)
            PFDivider529()
            Button {
                isTyping = false
                isPickingDay = true
            } label: {
                PFRow529(title: "By", trailing: endDay.map(TimingDates.weekdayDayMonth) ?? "you pick a date", showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("challenge-end")
        }
        .planCard529(padding: 16)
    }

    private var startButton: some View {
        let isDisabled = kind == nil || target == nil || endDay == nil
        return Button {
            guard let kind, let target, let endDay else { return }
            store.start(kind: kind, target: target, endDay: endDay)
            self.kind = nil
            targetText = ""
            self.endDay = nil
            isTyping = false
        } label: {
            TimingPrimaryLabel(title: "Start", isDisabled: isDisabled)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityIdentifier("challenge-start")
    }

    @ViewBuilder private var list: some View {
        if store.challenges.isEmpty {
            Text("You have no challenges.")
                .font(PFPlanFont543.text(13.5))
                .foregroundStyle(NoopLook.textSecondary)
        } else {
            ForEach(store.challenges.reversed()) { challenge in
                card(challenge)
            }
        }
    }

    private func card(_ challenge: AwardChallenge) -> some View {
        let progress = challenge.progress(days: store.days, activityDays: store.activityDays)
        let state = challenge.state(progress: progress, today: store.today)
        let pill: PFPill529
        switch state {
        case .running: pill = PFPill529(text: "Running", tone: .blue)
        case .finished: pill = PFPill529(text: "Finished", tone: .teal)
        case .ended: pill = PFPill529(text: "Ended", tone: .grey)
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.kind.phrase(challenge.target))
                        .font(PFPlanFont543.text(15, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                    Text("\(TimingDates.dayMonth(challenge.startDay)) to \(TimingDates.dayMonth(challenge.endDay)) \u{00B7} \(challenge.kind.sourceName)")
                        .font(PFPlanFont543.text(12.5))
                        .foregroundStyle(NoopLook.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                pill
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(progress)").lookNumeral(34).foregroundStyle(NoopLook.textPrimary)
                Text("of \(challenge.target)").font(PFPlanFont543.text(13.5)).foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                Button("Remove") { store.remove(challenge) }
                    .font(PFPlanFont543.text(12.5, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
            }
            ProgressView(value: min(Double(progress) / Double(max(challenge.target, 1)), 1))
                .tint(challenge.kind.color)
                .accessibilityHidden(true)
        }
        .planCard529(padding: 16)
        .containerIdentifier("challenge-card")
    }
}
