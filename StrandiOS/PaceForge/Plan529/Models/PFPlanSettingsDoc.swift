import Foundation

/// data/plan-settings.json: what the athlete decides, the rules the coach follows, the pace line.
struct PFPlanSettingsDoc: Codable, Equatable {
    var version: Int?
    var generatedAt: String?
    var youDecide: [Setting]?
    var coachFollows: [Rule]?
    var paces: String?

    struct Setting: Codable, Equatable {
        var key: String?
        var title: String?
        var sub: String?
        var value: Value?
        /// hours | days_off | priorities, or nil when the row only reads.
        var editable: String?
    }

    struct Rule: Codable, Equatable {
        var text: String?
        var sub: String?
    }

    /// A setting's value is a number (hours) or a list (days off); anything else reads as `.other` rather than failing the document.
    enum Value: Codable, Equatable {
        case number(Double)
        case list([String])
        case text(String)
        case other

        init(from decoder: Decoder) throws {
            let single = try decoder.singleValueContainer()
            if let number = try? single.decode(Double.self) {
                self = .number(number)
            } else if let list = try? single.decode([String].self) {
                self = .list(list)
            } else if let text = try? single.decode(String.self) {
                self = .text(text)
            } else {
                self = .other
            }
        }

        func encode(to encoder: Encoder) throws {
            var single = encoder.singleValueContainer()
            switch self {
            case .number(let number): try single.encode(number)
            case .list(let list): try single.encode(list)
            case .text(let text): try single.encode(text)
            case .other: try single.encodeNil()
            }
        }
    }
}
