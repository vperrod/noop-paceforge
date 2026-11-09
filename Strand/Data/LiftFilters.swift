import Foundation
#if canImport(WhoopStore)
import WhoopStore
#endif

// Lift exercise filters: the exercise pickers can narrow what they offer by muscle group (the primary muscle's
// region: push, pull, legs, trunk) and by equipment. The muscle comes from the tags an exercise already
// carries; equipment is a tag of its own, kept on this iPhone beside the name (it is not part of the stored
// exercise row or of a backup). Foundation only apart from the LiftMuscle vocabulary, so the matching is
// unit-tested.

enum LiftEquipment: String, CaseIterable, Codable, Identifiable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell, band, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbell"
        case .machine: return "Machine"
        case .cable: return "Cable"
        case .bodyweight: return "Bodyweight"
        case .kettlebell: return "Kettlebell"
        case .band: return "Band"
        case .other: return "Other"
        }
    }
}

extension LiftMuscle.Region {
    var filterName: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .trunk: return "Trunk"
        }
    }
}

/// The two optional narrowings of an exercise list. Both unset keeps everything.
struct LiftExerciseFilter: Equatable {
    var region: LiftMuscle.Region?
    var equipment: LiftEquipment?

    var isActive: Bool { region != nil || equipment != nil }

    /// An exercise matches a muscle group when its PRIMARY muscle is in that region, and matches an equipment
    /// when it is tagged with it. An exercise with no primary muscle, or no equipment tag, is left out of
    /// the filter that asks for the missing one.
    func matches(primary: LiftMuscle?, equipment tagged: LiftEquipment?) -> Bool {
        if let region, primary?.region != region { return false }
        if let equipment, tagged != equipment { return false }
        return true
    }

    /// `items` narrowed by the filter, in their own order.
    func apply<T>(_ items: [T], primary: (T) -> LiftMuscle?, name: (T) -> String,
                  equipmentOf: (String) -> LiftEquipment?) -> [T] {
        guard isActive else { return items }
        return items.filter { matches(primary: primary($0), equipment: equipmentOf(name($0))) }
    }
}

/// Equipment tags by exercise name, in UserDefaults. The name is compared without case or surrounding space,
/// the way the exercise vocabulary treats it.
enum LiftEquipmentStore {
    static let key = "noop.lift.equipment"

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func all(_ defaults: UserDefaults = .standard) -> [String: LiftEquipment] {
        guard let data = defaults.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return raw.compactMapValues(LiftEquipment.init(rawValue:))
    }

    static func equipment(for name: String, defaults: UserDefaults = .standard) -> LiftEquipment? {
        all(defaults)[normalized(name)]
    }

    /// Tags `name`, or clears its tag with nil. A blank name is ignored.
    static func set(_ equipment: LiftEquipment?, for name: String, defaults: UserDefaults = .standard) {
        let id = normalized(name)
        guard !id.isEmpty else { return }
        var map = all(defaults).mapValues(\.rawValue)
        map[id] = equipment?.rawValue
        if let data = try? JSONEncoder().encode(map) { defaults.set(data, forKey: key) }
    }
}
