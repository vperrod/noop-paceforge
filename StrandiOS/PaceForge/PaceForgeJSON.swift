import Foundation

/// A lenient, read-only view over decoded JSON. A missing key, a null or a value of an unexpected
/// type all read as nil / empty, so one odd field never blanks a whole PaceForge screen.
struct PFJ {
    let raw: Any?

    init(_ raw: Any?) { self.raw = raw }

    init(data: Data?) {
        guard let data else { self.raw = nil; return }
        self.raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    subscript(key: String) -> PFJ {
        PFJ((raw as? [String: Any])?[key])
    }

    subscript(index: Int) -> PFJ {
        guard let list = raw as? [Any], list.indices.contains(index) else { return PFJ(nil) }
        return PFJ(list[index])
    }

    var exists: Bool {
        guard let raw else { return false }
        return !(raw is NSNull)
    }

    var string: String? { raw as? String }

    var double: Double? { (raw as? NSNumber)?.doubleValue }

    /// Whole numbers beyond +-1e15 (millisecond timestamps are 1.7e12) read as missing: no count, minute or id the screens show
    /// is that large, and adding or subtracting two of them would overflow `Int`, which traps.
    var int: Int? {
        guard let number = raw as? NSNumber else { return nil }
        let value = number.doubleValue
        guard value.isFinite, abs(value) <= 1e15 else { return nil }
        return number.intValue
    }

    var bool: Bool? { raw as? Bool }

    /// Ids arrive as numbers in some files and strings in others.
    var idString: String? {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return String(n.int64Value) }
        return nil
    }

    var array: [PFJ] { (raw as? [Any])?.map { PFJ($0) } ?? [] }

    var dict: [String: PFJ] { (raw as? [String: Any])?.mapValues { PFJ($0) } ?? [:] }

    var strings: [String] { array.compactMap { $0.string } }

    /// The string, or nil when it is empty or only whitespace.
    var text: String? {
        guard let s = string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
