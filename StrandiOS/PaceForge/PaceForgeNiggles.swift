import Foundation

// Niggles: the small warnings (a knee, a calf) the athlete logs before they become the six-week injury. Foundation only, so it is
// compiled into the macOS unit-test bundle. The list is `data/niggles.json`; logging and resolving go through the job door
// (`niggle-add`, `niggle-resolve`, PaceForgeJob.swift).

/// The body areas `niggle-add` accepts, in the contract's order.
enum PFNiggleSite: String, CaseIterable, Equatable {
    case knee
    case calf
    case achilles
    case hamstring
    case hip
    case back
    case shoulder
    case other
}

struct PFNiggle: Equatable, Identifiable {
    let id: String
    let site: String
    let severity: Int?
    let date: String?
    let isOpen: Bool
}

enum PFNiggles {
    /// One niggle row: `{id, date, site, side, severity, movements, note, resolved}`; `resolved` is null while it is open.
    static func row(_ json: PFJ) -> PFNiggle? {
        guard let id = json["id"].idString, let site = json["site"].text else { return nil }
        return PFNiggle(id: id, site: site, severity: json["severity"].int, date: json["date"].text,
                        isOpen: json["resolved"].text == nil)
    }

    /// The file is a list of rows; a server that wraps it in `{"niggles": [...]}` reads the same.
    static func list(_ data: Data?) -> [PFNiggle] {
        let root = PFJ(data: data)
        let items = root.array.isEmpty ? root["niggles"].array : root.array
        return items.compactMap { row($0) }
    }

    /// The niggles still open, newest first.
    static func open(_ rows: [PFNiggle]) -> [PFNiggle] {
        rows.filter { $0.isOpen }.sorted { ($0.date ?? "") > ($1.date ?? "") }
    }
}

extension PFJobInputs {
    /// `niggle-add`: the area and how bad it is (1 to 5). The optional side, note, movements and date are left out.
    static func niggleAdd(site: PFNiggleSite, severity: Int) -> [String: Any]? {
        guard (1...5).contains(severity) else { return nil }
        return ["site": site.rawValue, "severity": severity]
    }

    /// `niggle-resolve`: the niggle's id, 8 hex digits.
    static func niggleResolve(id: String) -> [String: Any]? {
        let isHex = id.count == 8 && id.allSatisfy { "0123456789abcdef".contains($0) }
        return isHex ? ["id": id] : nil
    }
}
