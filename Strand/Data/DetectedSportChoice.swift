import Foundation
import StrandAnalytics

// MARK: - Detected stretch: the type to save it as, and the My Day walk setting
//
// A calm detected stretch of 15 minutes or more is saved as a Walk by itself (see `MyDayWalkPrefs`). Anything
// else stays a plain row on My Day; its long-press menu, and the one on a saved workout, name the type
// directly. The names below are the workout catalogue's own (`KnownWorkoutType`), so each saved row gets that
// sport's icon and dedupes like a hand-entered one.

enum DetectedSportChoice: String, CaseIterable, Identifiable {
    case walk, run, cycle, strength, hiit, yoga, hike, swim, other

    var id: String { rawValue }

    /// The stored sport label: the workout catalogue's display name.
    var sportName: String {
        switch self {
        case .walk: return "Walking"
        case .run: return "Running"
        case .cycle: return "Cycling"
        case .strength: return "Strength"
        case .hiit: return "HIIT"
        case .yoga: return "Yoga"
        case .hike: return "Hiking"
        case .swim: return "Pool swim"
        case .other: return "Other"
        }
    }

    var label: String {
        switch self {
        case .walk: return String(localized: "Walk")
        case .run: return String(localized: "Run")
        case .cycle: return String(localized: "Cycle")
        case .strength: return String(localized: "Strength")
        case .hiit: return String(localized: "HIIT / Cardio")
        case .yoga: return String(localized: "Yoga")
        case .hike: return String(localized: "Hike")
        case .swim: return String(localized: "Swim")
        case .other: return String(localized: "Other")
        }
    }
}

enum MyDayWalkPrefs {
    /// On unless the person switched it off in Settings. A calm stretch classified as a walk (15 minutes or more,
    /// finished) is saved as a Walk workout by itself the next time My Day or Today loads. It stays editable and
    /// deletable like any workout. The key is only ever written by the Settings toggle, so a person who never
    /// touched it (the setting used to default to off) has no stored value and gets the new default; an explicit
    /// off stays off.
    static let autoSaveKey = "noop.myday.autoSaveWalks"
    static var autoSaveEnabled: Bool { isAutoSaveEnabled(UserDefaults.standard) }

    static func isAutoSaveEnabled(_ defaults: UserDefaults) -> Bool {
        DetectedSegmentClassifier.autoSaveEnabled(stored: defaults.object(forKey: autoSaveKey) as? Bool)
    }
}

extension ProfileStore {
    /// What the walk-or-workout call needs from the profile: HRmax (override, else Tanaka) and where the
    /// person's own zone 3 starts. The resting HR comes from the nightly series in the loader.
    var segmentProfile: DetectedSegmentClassifier.Profile {
        DetectedSegmentClassifier.Profile(maxHr: Double(hrMax), restingHr: nil,
                                          zone3LowerBpm: hrZoneSet.zones.first(where: { $0.number == 3 })?.lower)
    }
}
