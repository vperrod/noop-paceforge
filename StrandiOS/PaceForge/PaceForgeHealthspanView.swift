import SwiftUI
import StrandDesign

// Healthspan, in the look: the HEALTHSPAN header with the days to the next weekly update, a week stepper, a hero card with our
// own drawn blob showing the BODY AGE AS A RANGE (never one precise number) and how many years younger or older that is, the
// PACE OF AGING ruler (-1.0x to 3.0x, a marker and a range whisker), GO TO links, the drivers with a 10-segment bar and the
// 6-month and 30-day averages, our assumptions and a trend card. It is our calculation of the published WHOOP Healthspan
// method, and says so; it is not WHOOP's number. Everything is read from healthspan.json (plus the weeks this phone has seen).

// MARK: - The blob

/// A small deterministic random source, so a blob keeps its shape between frames and between launches.
private struct PFSeeded {
    var state: UInt64

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

/// Our own organic ring: a slowly breathing outline with a soft glow and a few hundred drifting specks. Drawn with Canvas; no
/// artwork from anywhere. Still when Reduce Motion is on.
struct PFBodyAgeBlob: View {
    let color: Color
    let seed: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600)
            Canvas { context, size in
                Self.draw(&context, size: size, time: t, color: color, seed: seed)
            }
        }
        .accessibilityHidden(true)
    }

    /// How far the outline sits from a perfect circle at `angle`: three slow waves of different lengths.
    private static func wobble(angle: Double, time: Double, phases: [Double]) -> Double {
        let first: Double = 0.050 * sin(2 * angle + phases[0] + time * 0.35)
        let second: Double = 0.036 * sin(3 * angle + phases[1] - time * 0.27)
        let third: Double = 0.022 * sin(5 * angle + phases[2] + time * 0.50)
        return 1 + first + second + third
    }

    private static func outline(center: CGPoint, base: Double, time: Double, phases: [Double]) -> Path {
        var path = Path()
        let steps = 140
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * Double.pi
            let radius = base * wobble(angle: angle, time: time, phases: phases)
            let point = CGPoint(x: center.x + CGFloat(cos(angle) * radius), y: center.y + CGFloat(sin(angle) * radius))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func draw(_ context: inout GraphicsContext, size: CGSize, time: Double, color: Color, seed: Int) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = Double(min(size.width, size.height)) / 2 * 0.80
        var random = PFSeeded(state: UInt64(truncatingIfNeeded: seed) &+ 0x9E3779B97F4A7C15)
        let phases = [random.next() * 6.28, random.next() * 6.28, random.next() * 6.28]

        let shape = outline(center: center, base: base, time: time, phases: phases)
        // The glow: transparent in the middle, strongest at the edge.
        context.fill(shape, with: .radialGradient(Gradient(colors: [color.opacity(0), color.opacity(0.10), color.opacity(0.34)]),
                                                  center: center, startRadius: CGFloat(base * 0.35), endRadius: CGFloat(base * 1.04)))
        // The ring: a wide soft band and a thin bright line on it.
        context.stroke(shape, with: .color(color.opacity(0.22)), style: StrokeStyle(lineWidth: CGFloat(base * 0.16), lineJoin: .round))
        context.stroke(shape, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))

        // The specks: most near the ring, a few drifting inwards.
        for _ in 0..<240 {
            let angle = random.next() * 2 * Double.pi
            let depth = pow(random.next(), 0.55)
            let speed = (random.next() - 0.5) * 0.06
            let a = angle + time * speed
            let inward: Double = 1.02 - 0.46 * (1 - depth)
            let radius = base * wobble(angle: a, time: time, phases: phases) * inward
            let diameter = 0.9 + random.next() * 2.2
            let opacity = 0.25 + random.next() * 0.65
            let rect = CGRect(x: center.x + CGFloat(cos(a) * radius) - CGFloat(diameter / 2),
                              y: center.y + CGFloat(sin(a) * radius) - CGFloat(diameter / 2),
                              width: CGFloat(diameter), height: CGFloat(diameter))
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
        }
    }
}

// MARK: - The pace ruler

/// -1.0x to 3.0x as ticks, a marker at the pace and a whisker for its range. 1.0x is ageing as fast as the calendar.
struct PFPaceRuler: View {
    let value: Double
    let low: Double?
    let high: Double?
    let rangeLow: Double
    let rangeHigh: Double
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 14
            let width = max(size.width - inset * 2, 1)
            func x(_ pace: Double) -> CGFloat { inset + CGFloat(PFHealthspanFormat.paceFraction(pace, low: rangeLow, high: rangeHigh)) * width }
            let tickTop: CGFloat = 34
            let tickBottom: CGFloat = 62
            let hasRange = low != nil && high != nil
            let rangeStart = min(low ?? 0, high ?? 0)
            let rangeEnd = max(low ?? 0, high ?? 0)
            // Range whisker above the ticks.
            if let low, let high {
                let a = x(min(low, high)), b = x(max(low, high))
                var whisker = Path()
                whisker.move(to: CGPoint(x: a, y: 20))
                whisker.addLine(to: CGPoint(x: b, y: 20))
                context.stroke(whisker, with: .color(tint.opacity(0.7)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                for end in [a, b] {
                    var cap = Path()
                    cap.move(to: CGPoint(x: end, y: 14))
                    cap.addLine(to: CGPoint(x: end, y: 26))
                    context.stroke(cap, with: .color(tint.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            // Ticks every 0.1x; whole numbers are tall, halves medium.
            let steps = Safe.int(((rangeHigh - rangeLow) * 10))
            for step in 0...min(max(steps, 1), 400) {
                let pace = rangeLow + Double(step) / 10
                let isWhole = abs(pace - pace.rounded()) < 0.001
                let isHalf = abs(pace * 2 - (pace * 2).rounded()) < 0.001
                let top = isWhole ? tickTop - 6 : (isHalf ? tickTop - 2 : tickTop + 2)
                var tick = Path()
                tick.move(to: CGPoint(x: x(pace), y: top))
                tick.addLine(to: CGPoint(x: x(pace), y: tickBottom))
                let inRange = hasRange && pace >= rangeStart - 0.001 && pace <= rangeEnd + 0.001
                context.stroke(tick, with: .color(inRange ? NoopLook.textPrimary.opacity(0.75) : NoopLook.textMuted),
                               style: StrokeStyle(lineWidth: isWhole ? 1.6 : 1))
            }
            // The marker.
            var marker = Path()
            marker.move(to: CGPoint(x: x(value), y: 28))
            marker.addLine(to: CGPoint(x: x(value), y: tickBottom + 2))
            context.stroke(marker, with: .color(tint), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            var caret = Path()
            caret.move(to: CGPoint(x: x(value) - 6, y: 22))
            caret.addLine(to: CGPoint(x: x(value) + 6, y: 22))
            caret.addLine(to: CGPoint(x: x(value), y: 31))
            caret.closeSubpath()
            context.fill(caret, with: .color(tint))
            // Labels under the ruler.
            for label in [rangeLow, 1.0, rangeHigh] where label >= rangeLow && label <= rangeHigh {
                var anchor = UnitPoint.top
                var nudge: CGFloat = 0
                if label == rangeLow {
                    anchor = .topLeading
                    nudge = 2 - inset
                } else if label == rangeHigh {
                    anchor = .topTrailing
                    nudge = inset - 2
                }
                context.draw(Text(PFHealthspanFormat.paceText(label))
                                .font(LookFont.text(12, weight: .semibold))
                                .foregroundColor(NoopLook.textTertiary),
                             at: CGPoint(x: x(label) + nudge, y: tickBottom + 8), anchor: anchor)
            }
        }
        .frame(height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pace of aging \(PFHealthspanFormat.paceText(value))" + rangeSpoken)
        .accessibilityIdentifier("pf-pace-ruler")
    }

    private var rangeSpoken: String {
        guard let low, let high else { return "" }
        return ", range \(PFHealthspanFormat.paceRangeText(low: low, high: high))"
    }
}

// MARK: - Driver bar

/// The 10 segments of a driver, amber where a metric adds years and mint where it takes years off, with the 6-month average
/// above the bar and the last 30 days below it.
struct PFDriverSegments: View {
    let bar: PFDriverBar
    let sixMonthText: String?
    let thirtyDayText: String?

    private func color(at index: Int, filled: Bool) -> Color {
        let base: Color
        switch index {
        case 0...3: base = NoopLook.trendDown
        case 4...5: base = NoopLook.textTertiary
        default: base = NoopLook.trendUp
        }
        return filled ? base : base.opacity(0.22)
    }

    var body: some View {
        VStack(spacing: 5) {
            marker(position: bar.marker6m, caption: "6 MONTH AVG.", value: sixMonthText, pointsDown: true)
                .frame(height: 40)
            HStack(spacing: 2) {
                ForEach(0..<PFDriverBar.segments, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(at: index, filled: index < bar.filled))
                        .frame(height: 12)
                }
            }
            .accessibilityHidden(true)
            marker(position: bar.marker30d, caption: "30 DAY AVG.", value: thirtyDayText, pointsDown: false)
                .frame(height: 40)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var parts: [String] = []
        if let sixMonthText { parts.append("6 month average \(sixMonthText)") }
        if let thirtyDayText { parts.append("30 day average \(thirtyDayText)") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func marker(position: Double?, caption: String, value: String?, pointsDown: Bool) -> some View {
        GeometryReader { geo in
            if let position {
                let exact = CGFloat(position) * geo.size.width
                // The label is held inside the bar's edges; the triangle stays on the exact spot.
                let centre = min(max(exact, 48), max(geo.size.width - 48, 48))
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 1) {
                        Text(caption).lookCaps(9.5).foregroundStyle(NoopLook.textTertiary)
                        if let value {
                            Text(value).font(LookFont.numeral(15)).foregroundStyle(NoopLook.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .frame(width: 96, height: 28)
                    .position(x: centre, y: pointsDown ? 14 : 26)
                    LookTriangle(pointsUp: !pointsDown)
                        .fill(NoopLook.textPrimary)
                        .frame(width: 10, height: 7)
                        .position(x: exact, y: pointsDown ? 35 : 5)
                }
            }
        }
    }
}

// MARK: - A driver row

struct PFDriverRow: View {
    let driver: PFHealthDriver
    let pace: PFPaceOfAging?
    let scale: Double
    let isOpen: Bool
    let onToggle: () -> Void

    private var statusColor: Color {
        switch driver.status {
        case "meets": return NoopLook.trendUp
        case "short": return NoopLook.trendDown
        default: return NoopLook.textTertiary
        }
    }

    private var spokenYears: String {
        guard let years = driver.years else { return "no data" }
        return PFHealthspanFormat.yearsText(years) + " years"
    }

    private var yearsHeadline: String {
        driver.years.map { PFHealthspanFormat.yearsText($0) } ?? "\u{2013}"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(driver.label)
                        .lookCaps(12.5)
                        .foregroundStyle(NoopLook.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(yearsHeadline)
                            .font(LookFont.numeral(22))
                            .foregroundStyle(driver.isUnknown ? NoopLook.textTertiary : statusColor)
                        if !driver.isUnknown {
                            Text("yrs")
                                .font(LookFont.text(12, weight: .semibold))
                                .foregroundStyle(NoopLook.textTertiary)
                        }
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(driver.label), \(spokenYears)")
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("pf-driver-\(driver.key)-toggle")

            if isOpen { detail }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .containerIdentifier("pf-driver-\(driver.key)")
    }

    @ViewBuilder private var detail: some View {
        if driver.isUnknown {
            Text(driver.note ?? "No readings in the last six months, so this metric adds nothing to the range yet.")
                .font(LookFont.text(14, weight: .medium))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let bar = PFDriverBar.make(driver: driver, pace: pace, scale: scale)
            let thirty = pace?.metric(driver.key)?.years30d
            PFDriverSegments(bar: bar, sixMonthText: driver.valueText, thirtyDayText: thirty.map { "\(PFHealthspanFormat.yearsText($0)) yrs" })
                .accessibilityIdentifier("pf-driver-\(driver.key)-bar")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let low = driver.yearsLow, let high = driver.yearsHigh {
                    Text("Impact \(PFHealthspanFormat.yearsRangeText(low: low, high: high)) years")
                        .font(LookFont.text(14, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                }
                Spacer(minLength: 4)
                PFChip(text: driver.status == "meets" ? "Meets target" : "Short of target", color: statusColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                if let target = driver.targetText {
                    Text("Target: \(target)")
                        .font(LookFont.text(13, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                }
                if let note = driver.note {
                    Text(note)
                        .font(LookFont.text(12.5, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    PFSourceTag(source: driver.source)
                    if let coverage = driver.coverage, coverage < 0.9 {
                        Text("\(Safe.int((coverage * 100))) % of the six months has a reading")
                            .font(LookFont.text(12, weight: .medium))
                            .foregroundStyle(NoopLook.textTertiary)
                    }
                }
            }
            if let action = driver.action {
                PFIntelActionCard(action: action, identifier: "pf-driver-\(driver.key)-action")
            }
        }
    }
}

// MARK: - Screen

struct PFHealthspanScreen: View {
    @ObservedObject private var store = PFPhase4Store.shared

    var body: some View {
        PFDocScreen(title: "Healthspan", identifier: "pf-healthspan") {
            PFDocStateView(state: store.docs.healthspan, didLoad: store.didLoad, title: "Healthspan", icon: "hourglass",
                           identifier: "pf-healthspan") { healthspan, item in
                PFHealthspanBody(healthspan: healthspan, item: item, weeks: store.weeks)
            }
        }
    }
}

struct PFHealthspanBody: View {
    let healthspan: PFHealthspan
    let item: PFIntelItem
    let weeks: [PFHealthspanWeek]

    /// The week on screen; nil is the current week of the document.
    @State private var shownWeek: String?
    @State private var openDrivers: Set<String> = []
    private let hiding = PFHiding()

    private var currentWeek: String? { healthspan.pace?.week }

    /// Every week the phone knows, with the document's own week among them.
    private var allWeeks: [PFHealthspanWeek] {
        guard let entry = PFHealthspanHistory.entry(from: healthspan) else { return weeks }
        return PFHealthspanHistory.upserting(entry, into: weeks)
    }

    private var activeWeek: String? { shownWeek ?? currentWeek }
    private var isCurrent: Bool { shownWeek == nil || shownWeek == currentWeek }
    private var stored: PFHealthspanWeek? { allWeeks.first { $0.week == activeWeek } }

    // What the hero shows: the document's own range for the current week, a stored week's range otherwise.
    private var ageLow: Double? { isCurrent ? healthspan.bodyAge?.low : stored?.ageLow }
    private var ageHigh: Double? { isCurrent ? healthspan.bodyAge?.high : stored?.ageHigh }
    private var paceValue: Double? { isCurrent ? healthspan.pace?.value : stored?.paceValue }
    private var paceLow: Double? { isCurrent ? healthspan.pace?.low : stored?.paceLow }
    private var paceHigh: Double? { isCurrent ? healthspan.pace?.high : stored?.paceHigh }

    private var verdict: PFHealthspanFormat.AgeVerdict? {
        guard isCurrent, let range = healthspan.bodyAge?.yearsVsAge else { return nil }
        return PFHealthspanFormat.ageVerdict(range)
    }

    /// A number that stays the same for a week key across launches (String.hashValue does not), so a week keeps its shape.
    private static func stableSeed(_ key: String?) -> Int {
        (key ?? "").unicodeScalars.reduce(7) { ($0 &* 31) &+ Int($1.value) }
    }

    private var tint: Color {
        switch verdict?.direction {
        case .younger?: return NoopLook.trendUp
        case .older?: return NoopLook.trendDown
        default: return NoopLook.rest
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 18) {
                header
                weekStepper
                hero
                paceSection
                if isCurrent {
                    if let meaning = item.base.meaning {
                        LookInsightCard(hiding.text(meaning))
                            .accessibilityIdentifier("pf-healthspan-meaning")
                    }
                    goTo(proxy)
                    driversSection
                    assumptions
                } else {
                    LookInfoCard(title: "Earlier week",
                                 message: "The drivers are worked out for the current week only. Step forward to see them.")
                        .accessibilityIdentifier("pf-healthspan-earlier")
                }
                trend
                PFIntelFootnote(item: item)
            }
        }
        .containerIdentifier("pf-healthspan-body")
    }

    // MARK: Header and stepper

    private var header: some View {
        VStack(spacing: 4) {
            Text("HEALTHSPAN")
                .lookCaps(14)
                .foregroundStyle(NoopLook.textPrimary)
            if isCurrent, let asOf = healthspan.pace?.computedOn ?? healthspan.asOf,
               let next = PFHealthspanFormat.nextUpdateText(asOf: asOf) {
                Text(next)
                    .lookCaps(11)
                    .foregroundStyle(NoopLook.textTertiary)
                    .accessibilityIdentifier("pf-healthspan-next-update")
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }

    private var weekStepper: some View {
        let previous = activeWeek.flatMap { PFHealthspanHistory.neighbour(of: $0, step: -1, in: allWeeks) }
        let next = activeWeek.flatMap { PFHealthspanHistory.neighbour(of: $0, step: 1, in: allWeeks) }
        return HStack(spacing: 12) {
            stepButton("chevron.left", label: "Earlier week", target: previous)
            Text(activeWeek.flatMap(PFDocDate.weekRangeText) ?? "THIS WEEK")
                .lookCaps(13)
                .foregroundStyle(NoopLook.textPrimary)
                .accessibilityIdentifier("pf-healthspan-week")
            stepButton("chevron.right", label: "Later week", target: next)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(_ symbol: String, label: String, target: String?) -> some View {
        let direction = symbol == "chevron.left" ? "prev" : "next"
        return Button {
            shownWeek = (target == currentWeek) ? nil : target
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(target == nil ? NoopLook.textMuted : NoopLook.textPrimary)
                .frame(width: 36, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .accessibilityLabel(label)
        .accessibilityIdentifier("pf-healthspan-\(direction)-week")
    }

    // MARK: Hero

    @ViewBuilder private var hero: some View {
        if let low = ageLow, let high = ageHigh {
            ZStack {
                PFBodyAgeBlob(color: tint, seed: Self.stableSeed(activeWeek))
                VStack(spacing: 4) {
                    Text(PFHealthspanFormat.rangeText(low: low, high: high))
                        .font(LookFont.numeral(58))
                        .foregroundStyle(NoopLook.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityIdentifier("pf-body-age-range")
                    Text("BODY AGE")
                        .lookCaps(13)
                        .foregroundStyle(NoopLook.textSecondary)
                    if let verdict {
                        Text(verdict.text)
                            .font(LookFont.text(15, weight: .bold))
                            .foregroundStyle(tint)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("pf-body-age-verdict")
                    }
                }
                .padding(.horizontal, 54)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .containerIdentifier("pf-healthspan-hero")
        } else {
            LookInfoCard(title: "No body age range yet", message: noAgeMessage)
                .accessibilityIdentifier("pf-healthspan-no-age")
        }
    }

    private var noAgeMessage: String {
        guard let have = healthspan.inputsAvailable else { return "Not enough of the nine metrics have readings yet." }
        return "\(have) of \(healthspan.inputsTotal ?? 9) metrics have readings. It needs at least 6."
    }

    // MARK: Pace

    @ViewBuilder private var paceSection: some View {
        let pace = healthspan.pace
        VStack(alignment: .leading, spacing: 10) {
            Text("PACE OF AGING")
                .lookCaps(12)
                .foregroundStyle(NoopLook.textSecondary)
            if let value = paceValue {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(PFHealthspanFormat.paceText(value))
                        .font(LookFont.numeral(34))
                        .foregroundStyle(NoopLook.textPrimary)
                        .accessibilityIdentifier("pf-pace-value")
                    let chip = PFHealthspanFormat.paceChip(value)
                    PFChip(text: PFHealthspanFormat.chipText(chip),
                           color: chip == .slower ? NoopLook.trendUp : (chip == .faster ? NoopLook.trendDown : NoopLook.rest))
                        .accessibilityIdentifier("pf-pace-chip")
                    Spacer(minLength: 0)
                }
                PFPaceRuler(value: value, low: paceLow, high: paceHigh, rangeLow: pace?.rangeLow ?? -1,
                            rangeHigh: pace?.rangeHigh ?? 3, tint: tint)
                if let low = paceLow, let high = paceHigh {
                    Text("Likely between \(PFHealthspanFormat.paceRangeText(low: low, high: high)). 1.0x is ageing as fast as the calendar.")
                        .font(LookFont.text(12.5, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isCurrent, let basis = pace?.basis {
                    Text(PFFormat.capitalized(basis) + (pace?.carried == true ? ". Carried from earlier this week." : "."))
                        .font(LookFont.text(12.5, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(pace?.reason ?? "The pace needs a full week of the metrics before it can be worked out.")
                    .font(LookFont.text(14, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pf-pace-unavailable")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .containerIdentifier("pf-pace-card")
    }

    // MARK: GO TO and drivers

    private struct GroupRows: Identifiable {
        let group: PFDriverGroup
        let drivers: [PFHealthDriver]
        var id: String { group.rawValue }
    }

    private var groups: [GroupRows] {
        PFDriverGroup.allCases.compactMap { group -> GroupRows? in
            let inGroup = healthspan.drivers.filter { PFDriverGroup.of($0.key) == group }
            return inGroup.isEmpty ? nil : GroupRows(group: group, drivers: inGroup)
        }
    }

    private func goTo(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GO TO")
                .lookCaps(11)
                .foregroundStyle(NoopLook.textTertiary)
            LookFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(groups) { entry in
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("pf-group-\(entry.group.rawValue)", anchor: .top) }
                    } label: {
                        Text(entry.group.title)
                            .lookCaps(12)
                            .foregroundStyle(NoopLook.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Capsule(style: .continuous).fill(NoopLook.row))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pf-goto-\(entry.group.rawValue)")
                }
            }
        }
        .containerIdentifier("pf-healthspan-goto")
    }

    private var driversSection: some View {
        let scale = PFDriverBar.scale(healthspan.pace?.metrics ?? [], drivers: healthspan.drivers)
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(groups) { entry in
                VStack(alignment: .leading, spacing: 10) {
                    PFRuleLabel(entry.group.title.uppercased())
                        .id("pf-group-\(entry.group.rawValue)")
                    ForEach(entry.drivers) { driver in
                        PFDriverRow(driver: driver, pace: healthspan.pace, scale: scale, isOpen: openDrivers.contains(driver.key),
                                    onToggle: {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            if openDrivers.contains(driver.key) { openDrivers.remove(driver.key) } else { openDrivers.insert(driver.key) }
                                        }
                                    })
                    }
                }
            }
        }
        .containerIdentifier("pf-drivers")
    }

    // MARK: Assumptions

    @ViewBuilder private var assumptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOW THIS IS WORKED OUT")
                .lookCaps(11)
                .foregroundStyle(NoopLook.textTertiary)
            Text(healthspan.label ?? "Our calculation of the published WHOOP Healthspan method, not WHOOP's number.")
                .font(LookFont.text(14, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(healthspan.assumptions.enumerated()), id: \.offset) { _, line in
                Text("\u{2022} \(line)")
                    .font(LookFont.text(13, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let line = workedOutLine {
                Text(line)
                    .font(LookFont.text(12.5, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.insightRadius, style: .continuous).fill(NoopLook.cardDeep))
        .containerIdentifier("pf-healthspan-assumptions")
    }

    /// "Worked out for age 40, male, from 9 of 9 metrics over 182 days."
    private var workedOutLine: String? {
        guard let age = healthspan.age else { return nil }
        var who = "age \(Safe.int(age))"
        if let sex = healthspan.sex { who += ", \(sex)" }
        let have = healthspan.inputsAvailable ?? 0
        let total = healthspan.inputsTotal ?? 9
        let days = healthspan.windowDays ?? 182
        return "Worked out for \(who), from \(have) of \(total) metrics over \(days) days."
    }

    // MARK: Trend

    private var trendMetrics: [LookTrendMetric] {
        let calendar = Calendar.current
        func points(_ value: (PFHealthspanWeek) -> Double?) -> [LookPoint] {
            allWeeks.compactMap { week -> LookPoint? in
                guard let monday = PFDocDate.monday(ofWeek: week.week), let v = value(week), v.isFinite else { return nil }
                return LookPoint(date: calendar.startOfDay(for: PFFormat.date(monday)), value: v)
            }
        }
        return [
            LookTrendMetric(id: "body-age", title: "Body age (middle of the range)", icon: "hourglass", unit: "yrs", decimals: 1,
                            higherIsBetter: false, points: points { ($0.ageLow + $0.ageHigh) / 2 },
                            caption: "The middle of each week's range. The range itself is on the card above.",
                            info: LookTrendInfo(title: "What is body age?",
                                                message: "Our calculation of the published WHOOP Healthspan method from nine habits and fitness measures over six months. It is a range, not a precise number, and not WHOOP's number.")),
            LookTrendMetric(id: "pace", title: "Pace of aging", icon: "speedometer", unit: "x", decimals: 1, higherIsBetter: false,
                            points: points { $0.paceValue },
                            caption: "1.0x is ageing as fast as the calendar; below it is slower.",
                            info: LookTrendInfo(title: "What is the pace of aging?",
                                                message: "How fast your body age would move if the last 30 days carried on for six months. Below 1.0x you are ageing slower than the calendar.")),
        ]
    }

    @ViewBuilder private var trend: some View {
        let metrics = trendMetrics.filter { $0.points.count >= 2 }
        if metrics.isEmpty {
            let count = allWeeks.count
            let weeksText = count == 1 ? "1 week" : "\(count) weeks"
            LookInfoCard(title: "Trend",
                         message: "One point is added a week, the first time this phone sees that week. \(weeksText) so far; the chart appears from the second.")
                .accessibilityIdentifier("pf-healthspan-trend-empty")
        } else {
            LookTrendHost(metrics: metrics, initialRange: .sixMonths)
                .containerIdentifier("pf-healthspan-trend")
        }
    }
}

#if DEBUG
#Preview("Healthspan") {
    NavigationStack {
        ScrollView {
            PFHealthspanBody(healthspan: PFPhase4Sample.healthspan, item: PFPhase4Sample.item(PFDocID.healthspan),
                             weeks: PFPhase4Sample.weeks)
                .padding(16)
        }
        .lookScreenBackground()
    }
    .preferredColorScheme(.dark)
}
#endif
