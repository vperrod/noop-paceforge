import Foundation

/// The two keys added to the race results payload the results sheet reads: the biggest losses against the pacing plan, and the next block.
struct PFRaceLosses: Codable, Equatable {
    var losses: [Loss]?
    var nextBlock: String?

    struct Loss: Codable, Equatable {
        var segment: String?
        var delta: String?
        var note: String?
    }
}
