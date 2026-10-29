import Foundation

// Starting and ending easy mode from the app. Foundation only, so it is compiled into the macOS unit-test bundle. `easy-mode` only FILES a
// proposal (nothing changes until it is accepted, with the same answer a proposal in Needs you takes); `easy-mode-end` ends the running
// mode at once and restores the sessions still ahead (PaceForgeJob.swift).

/// How much easy mode takes off, in the contract's words: 1 light, 2 reduce, 3 rest-ish.
enum PFEasyLevel: Int, CaseIterable, Equatable {
    case light = 1
    case reduce = 2
    case restish = 3
}

enum PFEasyModeJobs {
    /// The days the app offers (the server clamps anything else to 3 to 14).
    static let days: ClosedRange<Int> = 3...14
    static let defaultLevel = PFEasyLevel.reduce
    static let defaultDays = 5

    /// The line after a start was filed: the server's note when it gave one (for example that it changed the days), else what happens next.
    static func filedLine(_ result: PFJ) -> String {
        result["note"].text.map { String($0.prefix(300)) } ?? "Proposed. Accept it to start."
    }

    /// The needs-you item that answers a proposal of easy-mode.json, if the snapshot has it.
    static func item(forProposal proposalID: String, in items: [PFNeedsItem]) -> PFNeedsItem? {
        items.first { $0.kind == .proposal && $0.proposalID == proposalID }
    }
}

extension PFJobInputs {
    /// `easy-mode`: `{"level": 1...3, "days": 3...14}`.
    static func easyMode(level: PFEasyLevel, days: Int) -> [String: Any]? {
        guard PFEasyModeJobs.days.contains(days) else { return nil }
        return ["level": level.rawValue, "days": days]
    }
}
