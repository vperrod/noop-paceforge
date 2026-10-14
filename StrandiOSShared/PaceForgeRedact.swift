import Foundation

/// Hide numbers, applied to words. The two Settings switches (the daily scores; body weight and body fat)
/// blank a number where the app draws it as a figure; this does the same for a number inside a sentence the
/// server wrote ("Recovery 74, strain 12.3 of 21", "Weight 82.4 kg"). Foundation only, and shared with the
/// widget extension, so the brief on the Lock Screen follows the same rule as the brief in the app.
///
/// It is deliberately a little greedy: a number next to a score word, or any weight in kilograms or pounds,
/// goes. Showing a number that should have been hidden is the failure that matters here; hiding the weight on
/// a barbell too is not.
enum PFRedact {
    /// What takes the place of a hidden number. Same word as `HideScoresPrefs.placeholder`.
    static let placeholder = "Hidden"

    enum Kind: Equatable {
        case scores
        case body
    }

    /// `text` with the numbers of the switched-on kinds replaced by `placeholder`. Unchanged when both are off.
    static func text(_ text: String, scores: Bool, body: Bool) -> String {
        guard scores || body, !text.isEmpty else { return text }
        var out = text
        if body { out = apply(bodyRules, to: out) }
        if scores { out = apply(scoreRules, to: out) }
        return out
    }

    /// Which switch covers a "Where you stand" metric, by its id in the server's norms pack.
    static func kind(forStandingMetric id: String) -> Kind? {
        switch id {
        case "body_fat", "ffmi", "waist_cm", "whtr", "bmi", "weight": return .body
        case "sleep_duration", "sleep_consistency": return .scores
        default: return nil
        }
    }

    // MARK: Rules

    private struct Rule {
        let regex: NSRegularExpression
        let template: String
    }

    private static let number = #"\d+(?:[.,]\d+)?"#
    /// A figure as the server writes one: "74", "74%", "12.3 of 21", "10-13", "62/100".
    private static let figure = #"(?>"# + number + #"(?:\s*[–-]\s*"# + number + #")?(?:\s*(?:/|of|out of)\s*\d+)?(?:\s*%)?)"#
    /// Words that may sit between a label and its figure: "Recovery is 74", "strain target 10-13", "**Recovery:** 74".
    private static let gap = #"(?:\s|[:=*_()–—-]|\b(?:is|was|at|of|score|scored|reading|target|around|about|near|came in at|sits at|stood at)\b){0,6}?"#
    /// A number that is really a duration or a speed is not a score ("Sleep 7h20", "Effort 20 min").
    private static let notAUnit = #"(?!\s*(?:h|hr|hrs|hours?|mins?|minutes?|m|s|km|:)(?![a-z]))"#

    private static let scoreWordsBare = #"recovery|charge|readiness|tss|rpe"#
    private static let scoreWords = scoreWordsBare + #"|strain|effort|sleep(?: score| performance| quality)?|rest score"#
    private static let bodyWords = #"body weight|weight|weigh(?:ed|s)?|body fat|bodyfat|fat mass|fat|bmi|lean mass|muscle mass|waist|hips"#

    private static func rule(_ pattern: String, _ template: String) -> Rule {
        // The patterns are literals in this file; a typo should fail loudly in the tests, not silently pass text through.
        // swiftlint:disable:next force_try
        Rule(regex: try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), template: template)
    }

    private static let scoreRules: [Rule] = [
        // "Recovery 74", "strain target 10-13", "Sleep score: 84%"
        rule(#"\b(\#(scoreWords))\b("# + gap + #")("# + figure + #")"# + notAUnit,
             "$1$2" + placeholder),
        // "74% recovery"
        rule(#"(?>"# + number + #"\s*%)(\s*(?:\#(scoreWordsBare))\b)"#,
             placeholder + "$1"),
        // "a score of 82", "scored 82"
        rule(#"\b(scores?|scored)\b((?:\s+(?:of|at|is|was))?\s*)"# + figure + notAUnit,
             "$1$2" + placeholder),
    ]

    private static let bodyRules: [Rule] = [
        // "82.4 kg", "-0.4 kg/week", "180 lb"
        rule(#"(?<![\w.])[-+−±]?(?>"# + number + #")\s*(?:kgs?|kilos?|kilograms?|lbs?|pounds?|st)\b(?:\s*/\s*(?:wk|week|day|month))?"#,
             placeholder),
        // "18.2% body fat"
        rule(#"(?>"# + number + #"\s*%)(\s*(?:body\s*)?fat\b)"#, placeholder + "$1"),
        // "Weight 82.4", "body fat 18.2%", "BMI 24.1", "waist 92.5"
        rule(#"\b(\#(bodyWords))\b("# + gap + #")("# + figure + #")(?!\s*(?:g|kcal|cal|reps?|sets?|x|km|min|bpm|days?)(?![a-z]))"#,
             "$1$2" + placeholder),
    ]

    private static func apply(_ rules: [Rule], to text: String) -> String {
        var out = text
        for rule in rules {
            let range = NSRange(out.startIndex..., in: out)
            out = rule.regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: rule.template)
        }
        return out
    }
}
