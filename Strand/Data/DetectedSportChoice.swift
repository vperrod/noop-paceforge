import Foundation
import StrandAnalytics

// MARK: - Detected stretch: the type to save it as, and the My Day walk setting
//
// My Day lists a sustained, raised-heart-rate stretch as a suggestion. Tapping Save uses the type the classifier
// guessed (Walk for a calm one); the type menu on the same button names it directly. The names below are the
// workout catalogue's own (`KnownWorkoutType`), so each saved row gets that sport's icon and dedupes like a
// hand-entered one.

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
    /// Off by default. When on, a calm stretch classified as a walk (15 minutes or more, finished) is saved as a
    /// Walk workout by itself the next time My Day loads. It stays editable and deletable like any workout.
    static let autoSaveKey = "noop.myday.autoSaveWalks"
    static var autoSaveEnabled: Bool { UserDefaults.standard.bool(forKey: autoSaveKey) }
}

extension ProfileStore {
    /// What the walk-or-workout call needs from the profile: HRmax (override, else Tanaka) and where the
    /// person's own zone 3 starts. The resting HR comes from the nightly series in the loader.
    var segmentProfile: DetectedSegmentClassifier.Profile {
        DetectedSegmentClassifier.Profile(maxHr: Double(hrMax), restingHr: nil,
                                          zone3LowerBpm: hrZoneSet.zones.first(where: { $0.number == 3 })?.lower)
    }
}
