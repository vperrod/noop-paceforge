#if DEBUG
import SwiftUI

// Made-up documents for the #Previews of the Phase 4 screens. Every figure is synthetic; nothing here is read from a server or
// from the athlete's data, and nothing here is compiled into a release build.

enum PFPhase4Sample {
    private static func metric(_ text: String) -> PFJ { PFJ(data: Data(text.utf8)) }

    /// The generic card fields every document item carries.
    static func item(_ id: String) -> PFIntelItem {
        var base = PFInsightItem(id: id, title: "Synthetic", available: true)
        base.meaning = "Synthetic meaning for a preview. Body age 35 to 38 against your 40. Pace of aging -0.6x (reversing)."
        base.confidence = "medium"
        base.dataNote = "Synthetic data note for a preview."
        return PFIntelItem(base: base, sources: ["Garmin", "PaceForge"])
    }

    static var healthspan: PFHealthspan {
        PFIntelDocsParse.healthspan(metric("""
        {"as_of": "2030-03-13", "label": "Our calculation of the published WHOOP Healthspan method, not WHOOP's number.", "age": 40.0,
         "sex": "male", "window_days": 182, "inputs_available": 9, "inputs_total": 9, "missing": [],
         "body_age": {"low": 35.2, "high": 37.9, "mid": 37, "text": "35 to 38", "years_vs_age": {"low": -4.8, "high": -2.1, "mid": -3.4}},
         "pace": {"available": true, "week": "2030-W11", "computed_on": "2030-03-13", "carried": false, "value": -0.6, "low": -1.0,
                  "high": 2.2, "label": "reversing", "range": [-1.0, 3.0], "basis": "the last 30 days held for 6 months, on 9 metrics",
                  "metrics": [{"key": "sleep_duration", "label": "Sleep duration", "years_6m": 0.4, "years_30d": 0.9},
                              {"key": "vo2max", "label": "VO2max", "years_6m": -3.5, "years_30d": -3.6},
                              {"key": "strength", "label": "Strength time", "years_6m": 0.8, "years_30d": 0.3}]},
         "drivers": [
           {"key": "vo2max", "label": "VO2max", "unit": "ml/kg/min", "source": "Garmin", "target_text": "39 or more", "value_text": "54.3 ml/kg/min",
            "coverage": 1.0, "status": "meets", "years": -3.5, "years_low": -4.6, "years_high": -2.4,
            "action": {"id": "a1", "text": "Keep your hard interval sessions.", "why": "Synthetic reason.", "effort": {"value": 0, "unit": "min", "label": "no extra time"}}},
           {"key": "sleep_duration", "label": "Sleep duration", "unit": "h", "source": "Garmin", "target_text": "7 to 9 h", "value_text": "6.4 h",
            "coverage": 0.98, "status": "short", "years": 0.4, "years_low": 0.2, "years_high": 0.6,
            "action": {"id": "a2", "text": "Add 45 minutes to your sleep window.", "why": "Synthetic reason.", "effort": {"value": 45, "unit": "min/day", "label": "45 min/day"}}},
           {"key": "strength", "label": "Strength time", "unit": "min/week", "source": "Garmin", "target_text": "more than 40 min a week", "value_text": "12 min/week",
            "coverage": 1.0, "status": "short", "years": 0.8, "years_low": 0.4, "years_high": 1.3}],
         "assumptions": ["Synthetic assumption one.", "Synthetic assumption two."]}
        """)) ?? PFHealthspan()
    }

    static var weeks: [PFHealthspanWeek] {
        (0..<5).map { n in
            PFHealthspanWeek(week: String(format: "2030-W%02d", 7 + n), asOf: "2030-02-20", ageLow: 36.0 - Double(n) * 0.2,
                             ageHigh: 39.0 - Double(n) * 0.2, paceValue: 0.6 - Double(n) * 0.2, paceLow: -0.5, paceHigh: 1.8)
        }
    }

    static var journalImpact: PFJournalImpact {
        PFIntelDocsParse.journalImpact(metric("""
        {"as_of": "2030-03-13", "window_days": 90, "min_each": 5,
         "outcome": {"key": "charge", "label": "Charge (NOOP)", "source": "NOOP", "unit": "%", "days": 90},
         "hurts": [{"id": "late_meal", "label": "A meal after 21:00", "n_with": 12, "n_without": 70, "mean_with": 52.0, "mean_without": 61.0, "pct": -14.8, "t": -2.6,
                    "clear": true, "strong": true, "confidence": "medium", "note": "Synthetic note.",
                    "action": {"id": "x1", "text": "Eat earlier.", "why": "Synthetic.", "effort": {"value": 0, "unit": "min", "label": "no extra time"}}},
                   {"id": "alcohol", "label": "Alcohol", "n_with": 9, "n_without": 80, "pct": -6.2, "clear": true}],
         "helps": [{"id": "easy_day", "label": "An easy day", "n_with": 30, "n_without": 60, "pct": 9.1, "clear": true, "strong": true}],
         "no_clear_effect": [{"id": "short_sleep", "label": "A night under 7 hours", "n_with": 66, "n_without": 22, "pct": -2.1}],
         "not_enough_data": [{"id": "late_session", "label": "A session after 20:00", "n_with": 1, "n_without": 89}], "tested": 5}
        """)) ?? PFJournalImpact(minEach: 5)
    }

    static var highlights: PFHighlights {
        PFIntelDocsParse.highlights(metric("""
        {"as_of": "2030-03-13", "noop_since": "2030-02-01", "garmin_since": "2029-01-01",
         "records": [
           {"id": "rest", "label": "Rest", "periods": [{"id": "all", "label": "All time", "noop": {"value": 83.1, "display": "Rest 83 %", "date": "2030-03-11", "source": "NOOP"},
              "garmin": {"value": 90.0, "display": "Sleep score 90", "date": "2029-06-01", "source": "Garmin", "label": "Sleep score (Garmin)"}}]},
           {"id": "charge", "label": "Charge", "periods": [{"id": "all", "label": "All time", "noop": {"value": 95.8, "display": "Charge 96 %", "date": "2030-03-12", "source": "NOOP"}}]},
           {"id": "effort", "label": "Effort", "periods": [{"id": "all", "label": "All time", "noop": {"value": 70.8, "display": "Effort 14.9 of 21", "date": "2030-03-10", "source": "NOOP"}}]}],
         "streaks": [
           {"id": "rest_70", "label": "Rest 70 % or more", "source": "NOOP", "unit": "days", "current": 6, "best": 9, "alive": true, "line": "Synthetic line about the streak."},
           {"id": "charge_green", "label": "Green Charge", "source": "NOOP", "unit": "days", "current": 2, "best": 4, "alive": true},
           {"id": "effort_10", "label": "Effort 10 or more", "source": "NOOP", "unit": "days", "current": 0, "best": 4, "alive": false}],
         "notable": [{"id": "rhr_low", "label": "Lowest resting heart rate", "value": 39.0, "display": "39 bpm", "date": "2029-06-01", "days_ago": 285, "source": "Garmin"},
                     {"id": "sleep_longest", "label": "Longest sleep", "value": 9.0, "display": "8 h 59", "date": "2030-03-01", "days_ago": 12, "source": "Garmin"}]}
        """)) ?? PFHighlights()
    }

    static var monthly: PFMonthlyReport {
        PFIntelDocsParse.monthlyReport(metric("""
        {"as_of": "2030-03-13", "periods": [{"id": "last_full", "label": "February 2030", "days": 28, "compared_with": "January 2030",
           "metrics": [{"key": "charge", "label": "Charge", "unit": "%", "source": "NOOP", "state": "ok", "current": {"value": 61.2}, "previous": {"value": 70.4},
                        "delta": -9.2, "direction": "down", "assessment": "worse", "series_label": "Charge (NOOP)"},
                       {"key": "weight", "label": "Weight", "unit": "kg", "state": "not enough data", "reason": "0 readings this month; 2 are needed"}],
           "movers": [{"key": "charge", "label": "Charge (NOOP)", "unit": "", "source": "NOOP", "previous": 70.4, "current": 61.2, "pct": -13.1, "assessment": "worse",
                       "what_moved": [{"sentence": "Synthetic link sentence."}]}]}],
         "goals": {"weight": {"target_kg": 87.0, "kg_to_go": 3.9, "text": "Synthetic weight sentence.", "status": "behind"}},
         "focus": [{"text": "Fix the wake time.", "why": "Synthetic why.", "effort": "no extra time"}]}
        """)) ?? PFMonthlyReport()
    }

    static var plan: PFMyPlan {
        PFIntelDocsParse.myPlan(metric("""
        {"as_of": "2030-03-13", "planned_sessions": 8, "done": 5, "partial": 1, "missed": 0, "pct_accomplished": 62, "days_left": 5,
         "next_item": {"label": "Synthetic class", "weekday": "Thu", "minutes": 45},
         "items": [{"label": "Synthetic intervals", "done": true, "weekday": "Mon", "status": "done", "minutes": 30, "hard": true},
                   {"label": "Synthetic easy run", "done": true, "weekday": "Tue", "status": "partial", "minutes": 35},
                   {"label": "Synthetic strength", "done": false, "weekday": "Wed", "status": "today", "minutes": 40},
                   {"label": "Synthetic class", "done": false, "weekday": "Thu", "status": "upcoming", "minutes": 45}]}
        """)) ?? PFMyPlan(planned: 0, done: 0, partial: 0, missed: 0)
    }
}
#endif
