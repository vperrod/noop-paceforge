import Foundation

/// Short "how it works" text for the wave-3 cards, bundled so the (i) button works before the server's
/// metric-explainers.json carries these ids. The server's own entry wins whenever it has one. Written from
/// what each card shows, with no claims beyond that. Foundation only, so it is in the unit-test bundle too.
enum PFLocalExplainers {
    static let raceWeek = "race_week"
    static let raceSims = "hyrox_sims"
    static let easyMode = "easy_mode"
    static let muscleCheck = "muscle_check"
    static let tape = "tape"
    static let heat = "heat"

    static let fallback: [String: PFExplainer] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    private static let all: [PFExplainer] = [
        PFExplainer(
            id: raceWeek, title: "Race week",
            plain: "When a race is close, PaceForge switches to a race-week plan. This card replaces the normal race countdown until the race has passed.",
            how: "The phase (taper, race eve, race day or recovery), the volume target, the carb-load figure, the checklist and the race-morning timeline all come from your PaceForge server. Nothing here is calculated on the phone.",
            caveat: "Ticks on the checklist are kept only on this iPhone, one list per race. The app does not send them anywhere."),
        PFExplainer(
            id: raceSims, title: "Race simulations",
            plain: "Your logged race simulations against your goal time. Each run and station is shown against the goal split and against your previous simulation.",
            how: "Run fade, compromised-run percentages and the pacing check are worked out by your PaceForge server from the run splits you logged. The pacing line says whether the biggest deviation stayed inside the 5 % band.",
            caveat: "Garmin sessions that look like a simulation but could not be split into runs and stations are counted as unmapped and left out."),
        PFExplainer(
            id: easyMode, title: "Easy mode",
            plain: "Easy mode is a temporary, lighter version of your plan. It has a level, a number of days and a date it returns on.",
            how: "You start, accept or end it in Telegram. This app only shows its state and any proposal waiting for your answer.",
            caveat: "Restorable means the server says the sessions the mode changed can be put back."),
        PFExplainer(
            id: muscleCheck, title: "Muscle check",
            plain: "A check on whether weight changes look like fat or like lean mass, from your scale readings.",
            how: "The lean trend and the weekly change smooth your readings; the noise band is how far a single reading can wander. The 14 and 28 day split divides the weight change into lean and fat, and its label says estimate or noisy.",
            caveat: "A split labelled noisy is within the scale's noise and is not a reason to act. Calibrating means there are not enough readings yet."),
        PFExplainer(
            id: tape, title: "Tape measurements",
            plain: "Your logged tape measurements by site, with the change over 28 days where there are enough readings.",
            how: "You log measurements in Telegram. Waist-to-hip is the waist divided by the hips on the same day.",
            caveat: "Tape measurements vary with how the tape is held, so a small change is not a trend."),
        PFExplainer(
            id: heat, title: "Heat on a session",
            plain: "How warm it was for a session and what it cost your pace.",
            how: "The server rates the heat from the temperature, the feels-like temperature and the humidity, and estimates the pace cost.",
            caveat: "The pace cost is an estimate, not a measurement."),
    ]
}
