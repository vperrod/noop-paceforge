#if !os(watchOS)
import SwiftUI

// MARK: - Look atoms
//
// The small pieces the look's components share: the trend triangle, the notched card, the legend strip, the
// monitor tile, the section header, the Daily Outlook bar and the "what is it" card. Plain value inputs only
// (no environment objects), so each previews on its own.

// MARK: Triangle

/// The small trend triangle (10 x 7).
public struct LookTriangle: Shape {
    public var pointsUp: Bool

    public init(pointsUp: Bool) { self.pointsUp = pointsUp }

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        if pointsUp {
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

/// A triangle coloured by what it means for this metric.
public struct LookTriangleMark: View {
    public var mark: LookTodayMark

    public init(_ mark: LookTodayMark) { self.mark = mark }

    public var body: some View {
        LookTriangle(pointsUp: mark.pointsUp)
            .fill(NoopLook.color(forTone: mark.tone))
            .frame(width: 10, height: 7)
            .accessibilityHidden(true)
    }
}

// MARK: Notched card

/// The card under a dial: a 12 pt rounded card with a small notch pointing up at the dial above it.
public struct LookNotchCard<Content: View>: View {
    public var showsNotch: Bool
    @ViewBuilder public var content: () -> Content

    public init(showsNotch: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.showsNotch = showsNotch
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
            .overlay(alignment: .top) {
                if showsNotch {
                    LookTriangle(pointsUp: true)
                        .fill(NoopLook.card)
                        .frame(width: 20, height: 9)
                        .offset(y: -9)
                }
            }
    }
}

/// A 64 pt row: icon, caps label, then the caller's trailing content.
struct LookRowFrame<Trailing: View>: View {
    let icon: String
    let label: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(NoopLook.textSecondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(label)
                .lookCaps(12.5)
                .foregroundStyle(NoopLook.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .frame(height: 64)
    }
}

// MARK: Legend strip

/// The strip at the foot of a comparison card: the two triangles and what they compare against.
public struct LookLegend: View {
    public var leading: String
    public var trailing: String

    public init(leading: String = "Today", trailing: String = "vs. last 30 days") {
        self.leading = leading
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 8) {
            LookTriangle(pointsUp: true).fill(NoopLook.trendUp).frame(width: 10, height: 7)
            LookTriangle(pointsUp: false).fill(NoopLook.trendDown).frame(width: 10, height: 7)
            Text(leading)
                .font(LookFont.text(13, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
            Text(trailing)
                .font(LookFont.text(13, weight: .medium))
                .foregroundStyle(NoopLook.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(NoopLook.cardDeep))
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(leading) \(trailing). Green marks are better than usual, orange are worse.")
    }
}

// MARK: Monitor tile

/// A Health / Stress monitor tile: caps title, a badge, a status word in the reading's colour and a detail line.
public struct MonitorTile: View {
    public enum Badge: Equatable {
        case symbol(String)
        case text(String)
    }

    public var title: String
    public var badge: Badge
    public var badgeForeground: Color
    public var badgeBackground: Color
    public var status: String
    public var statusColor: Color
    public var detail: String
    public var action: (() -> Void)?

    public init(title: String, badge: Badge, badgeForeground: Color, badgeBackground: Color,
                status: String, statusColor: Color, detail: String, action: (() -> Void)? = nil) {
        self.title = title
        self.badge = badge
        self.badgeForeground = badgeForeground
        self.badgeBackground = badgeBackground
        self.status = status
        self.statusColor = statusColor
        self.detail = detail
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { tile }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
        } else {
            tile
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .lookCaps(13)
                    .foregroundStyle(NoopLook.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 9) {
                badgeView
                VStack(alignment: .leading, spacing: 0) {
                    Text(status)
                        .font(LookFont.text(13.5, weight: .bold))
                        .tracking(13.5 * 0.07)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(detail)
                        .font(LookFont.text(13, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.tile))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(status). \(detail)")
    }

    @ViewBuilder private var badgeView: some View {
        switch badge {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(badgeForeground)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(badgeBackground))
        case .text(let value):
            Text(value)
                .font(LookFont.numeral(15))
                .foregroundStyle(badgeForeground)
                .frame(minWidth: 24, minHeight: 24)
                .padding(.horizontal, value.count > 1 ? 5 : 0)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(badgeBackground))
        }
    }
}

// MARK: Section header

/// "My Day" with the white plus button.
public struct LookSectionHeader: View {
    public var title: String
    public var onAdd: (() -> Void)?

    public init(_ title: String, onAdd: (() -> Void)? = nil) {
        self.title = title
        self.onAdd = onAdd
    }

    public var body: some View {
        HStack {
            Text(title)
                .font(LookFont.text(22, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
            Spacer(minLength: 8)
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to \(title)")
            }
        }
    }
}

// MARK: Daily Outlook bar

/// The warm-to-cool bar that opens the day's outlook. `isExpanded` nil draws a chevron-right (it opens
/// something); a Bool draws a chevron that turns down while the content below it is open.
public struct OutlookBar: View {
    public var text: String
    public var isExpanded: Bool?
    public var action: () -> Void

    public init(_ text: String = "Your Daily Outlook", isExpanded: Bool? = nil, action: @escaping () -> Void) {
        self.text = text
        self.isExpanded = isExpanded
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "sun.max")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.white)
                    .accessibilityHidden(true)
                Text(text)
                    .font(LookFont.text(15, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .rotationEffect(.degrees(isExpanded == true ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: NoopLook.outlookBar, startPoint: .leading, endPoint: .trailing))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: Info card

/// The "What is it?" card at the foot of a trend or detail screen.
public struct LookInfoCard: View {
    public var title: String
    public var message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(LookFont.text(19, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(LookFont.text(15, weight: .medium))
                .foregroundStyle(NoopLook.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.insightRadius, style: .continuous).fill(NoopLook.cardDeep))
    }
}

#if DEBUG
#Preview("Atoms") {
    VStack(spacing: 14) {
        HStack(spacing: 12) {
            MonitorTile(title: "Health monitor", badge: .symbol("exclamationmark"), badgeForeground: Color(hex: "#E8505A"),
                        badgeBackground: NoopLook.alertWash, status: "VERY ELEVATED", statusColor: NoopLook.alert,
                        detail: "Respiratory rate")
            MonitorTile(title: "Stress monitor", badge: .text("1.7"), badgeForeground: NoopLook.stressMedium,
                        badgeBackground: Color(hex: "#344745"), status: "MEDIUM", statusColor: NoopLook.stressMedium,
                        detail: "08:53")
        }
        LookSectionHeader("My Day", onAdd: {})
        OutlookBar(action: {})
        LookNotchCard {
            LookRowFrame(icon: "waveform.path.ecg", label: "Heart rate variability") {
                Text("43").font(LookFont.numeral(25)).foregroundStyle(NoopLook.textPrimary)
            }
            LookLegend()
        }
        LookInfoCard(title: "What is heart rate variability?",
                     message: "The variation in time between heartbeats while you sleep. Compare it with your own normal.")
    }
    .padding(16)
    .frame(width: 402)
    .lookScreenBackground()
    .preferredColorScheme(.dark)
}
#endif
#endif
