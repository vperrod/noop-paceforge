import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Look type
//
// Numerals use D-DIN (SIL Open Font License, Datto Inc.; files and licence in StrandiOS/Resources/Fonts,
// registered through UIAppFonts). If the face is not in the bundle (a package preview, the macOS app, a
// failed registration) every numeral falls back to the system rounded face in its condensed width, so a
// missing font changes the look slightly and never the layout contract (all numerals are fixed-size).
//
// Labels are bold system type in capitals with 0.1em tracking.

public enum LookFont {

    public static let boldName = "D-DIN-Bold"
    public static let regularName = "D-DIN"
    public static let condensedBoldName = "D-DINCondensed-Bold"

    /// True when D-DIN is registered in this process. Resolved once: font registration happens at launch.
    public static let isDDINAvailable: Bool = {
        #if canImport(UIKit)
        return UIFont(name: boldName, size: 12) != nil
        #elseif canImport(AppKit)
        return NSFont(name: boldName, size: 12) != nil
        #else
        return false
        #endif
    }()

    /// The numeral face at a fixed size: D-DIN Bold, else system rounded bold in condensed width.
    public static func numeral(_ size: CGFloat) -> Font {
        if isDDINAvailable {
            return Font.custom(boldName, fixedSize: size).monospacedDigit()
        }
        return Font.system(size: size, weight: .bold, design: .rounded).width(.condensed).monospacedDigit()
    }

    /// The regular-weight numeral (the small grey baseline under a "today vs. 30 days" value).
    public static func numeralRegular(_ size: CGFloat) -> Font {
        if isDDINAvailable {
            return Font.custom(regularName, fixedSize: size).monospacedDigit()
        }
        return Font.system(size: size, weight: .medium, design: .rounded).width(.condensed).monospacedDigit()
    }

    /// The narrow bold numeral for tight places (sticky mini dials, tab-bar-sized figures).
    public static func numeralCondensed(_ size: CGFloat) -> Font {
        if isDDINAvailable {
            return Font.custom(condensedBoldName, fixedSize: size).monospacedDigit()
        }
        return Font.system(size: size, weight: .bold, design: .rounded).width(.condensed).monospacedDigit()
    }

    /// Body text face (system; the reference's text face is a geometric sans and the system face is the
    /// nearest one that needs no bundled font).
    public static func text(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        Font.system(size: size, weight: weight)
    }

    /// Tracking for caps labels: 0.1em.
    public static func capsTracking(forSize size: CGFloat) -> CGFloat { size * 0.1 }
}

public extension View {
    /// A caps label: bold, uppercase, 0.1em tracking. Colour is left to the caller.
    func lookCaps(_ size: CGFloat = 13, weight: Font.Weight = .bold) -> some View {
        self.font(LookFont.text(size, weight: weight))
            .tracking(LookFont.capsTracking(forSize: size))
            .textCase(.uppercase)
    }

    /// A numeral in the look's face at a fixed size.
    func lookNumeral(_ size: CGFloat) -> some View {
        self.font(LookFont.numeral(size))
    }
}
