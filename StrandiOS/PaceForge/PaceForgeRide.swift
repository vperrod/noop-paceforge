import Foundation

// Bike rides: PaceForge's ride-metrics.json (one entry per ride, keyed "bike:<date>"), the per-ride stream
// file, and the ride rows in day-events.json. Foundation only, so the parsing, the 600-point downsampling and
// the formatting below are compiled into the macOS unit-test bundle as well.
//
// A ride is a bike session: the words here are power, heart rate, cadence in rpm and kilojoules, never the
// running vocabulary. Every field is optional on the wire; a missing one hides its part of the screen.

// MARK: - Model

struct PFRideZone: Identifiable, Equatable {
    var zone: Int
    var name: String?
    /// The zone's lower and upper edge: watts for a power zone, bpm for a heart-rate zone.
    var low: Double?
    var high: Double?
    var secs: Double
    /// Share of the ride in the zone as the server sends it, 0 to 100.
    var pct: Double?
    var id: Int { zone }

    /// "150\u{2013}200", "250+" or nil.
    var rangeText: String? {
        switch (low, high) {
        case let (low?, high?): return "\(Int(low.rounded()))\u{2013}\(Int(high.rounded()))"
        case let (low?, nil): return "\(Int(low.rounded()))+"
        case let (nil, high?): return "up to \(Int(high.rounded()))"
        default: return nil
        }
    }
}

struct PFRideLap: Identifiable, Equatable {
    var n: Int
    var name: String?
    var startS: Double?
    var endS: Double?
    var secs: Double?
    var avgPower: Double?
    var pctFtp: Double?
    var targetPower: Double?
    /// Average power against the lap's target, in percent (positive = above the target).
    var vsTargetPct: Double?
    var avgHr: Double?
    var id: Int { n }
}

struct PFRidePause: Equatable {
    var start: Double
    var end: Double
}

struct PFRideMMP: Equatable {
    var seconds: Int
    var watts: Double
}

struct PFRideDecoupling: Equatable {
    var pct: Double?
    var valid: Bool?
    var hrDriftBpm: Double?

    /// "3.2 %" when the figure is valid, "Not valid" when it is not or when there is no figure.
    var text: String {
        guard valid == true, let pct else { return "Not valid" }
        return String(format: "%.1f %%", pct)
    }
    var isValid: Bool { valid == true && pct != nil }
}

struct PFRide: Identifiable {
    /// The server's ride id, "bike:<date>".
    var id: String
    /// The part after "bike:"; it may carry a time, and is what the stream and analysis files are named by.
    var dateKey: String
    var workout: String?
    /// "1hz" (second by second) or "240pt" (a 240-point sample of the ride).
    var resolution: String?
    /// False only when the server says the ride has no stream file.
    var hasStream = true
    var samples: Int?
    var ftp: Double?
    var durationS: Double?
    var avgPower: Double?
    var np: Double?
    var intensityFactor: Double?
    var tss: Double?
    var vi: Double?
    var kj: Double?
    var kcalEstimate: Double?
    var avgHr: Double?
    var ef: Double?
    var decoupling: PFRideDecoupling?
    var powerZones: [PFRideZone] = []
    var hrZones: [PFRideZone] = []
    var mmp: [PFRideMMP] = []
    var laps: [PFRideLap] = []
    var compliance: String?
    /// The raw `hrr1` object; the screen decodes it with the same reader the session results use.
    var hrr1 = PFJ(nil)
    var type: String?
    var summaryLine: String?

    /// The ride's day, yyyy-MM-dd.
    var date: String { String(dateKey.prefix(10)) }

    var isLowResolution: Bool { (resolution ?? "").lowercased() == "240pt" }

    /// Under the title: how finely the ride was recorded.
    var resolutionNote: String { isLowResolution ? "240-point sample" : "second-by-second" }

    /// Under the coach analysis when the ride is only a sample.
    var estimateNote: String? { isLowResolution ? "Estimated from a 240-point sample" : nil }

    /// `data/bike/streams/<date with ':' replaced by '-'>.json`
    var streamPath: String { "data/bike/streams/" + dateKey.replacingOccurrences(of: ":", with: "-") + ".json" }

    /// `data/analyses/bike:<date>.md` (the colon stays in the path).
    var analysisPath: String { "data/analyses/bike:" + dateKey + ".md" }

    var title: String { workout ?? "Ride" }

    /// "60 min \u{00B7} avg 160 W \u{00B7} NP 188 W \u{00B7} TSS 62 \u{00B7} avg HR 148 bpm" for a row.
    var rowLine: String {
        var bits: [String] = []
        if let durationS, durationS > 0 { bits.append(PFRideFormat.minutes(durationS)) }
        if let avgPower { bits.append("avg \(Int(avgPower.rounded())) W") }
        if let np { bits.append("NP \(Int(np.rounded())) W") }
        if let tss { bits.append("TSS \(Int(tss.rounded()))") }
        if let avgHr { bits.append("avg HR \(Int(avgHr.rounded())) bpm") }
        return bits.joined(separator: " \u{00B7} ")
    }
}

/// A ride row of day-events.json: a workout with a ride id and no Garmin activity.
struct PFRideEvent: Equatable {
    var rideId: String
    var date: String
    var startTs: Int?
    var endTs: Int?
    var title: String?
    var avgPower: Double?
    var np: Double?
    var tss: Double?
    var avgHr: Double?
    var durationMin: Double?
}

/// The per-ride stream: parallel arrays on a common time axis, nulls for missing readings.
struct PFRideStream {
    var hz: Double?
    var rideId: String?
    var startMs: Double?
    var workout: String?
    var ftp: Double?
    var t: [Double] = []
    var power: [Double?] = []
    var hr: [Double?] = []
    var cadence: [Double?] = []
    var speed: [Double?] = []
    var distanceM: [Double?] = []
    var targetPower: [Double?] = []
    var laps: [PFRideLap] = []
    var pauses: [PFRidePause] = []

    var hasPower: Bool { power.contains { $0 != nil } }
    var hasHr: Bool { hr.contains { $0 != nil } }
    var hasCadence: Bool { cadence.contains { $0 != nil } }
    var hasTarget: Bool { targetPower.contains { $0 != nil } }
    var duration: Double { t.last ?? 0 }
}

// MARK: - Formatting

enum PFRideFormat {
    /// 3725 -> "1:02:05", 125 -> "2:05".
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// 3600 -> "60 min", 5400 -> "90 min", 40 -> "40 s".
    static func minutes(_ seconds: Double) -> String {
        seconds < 60 ? "\(Int(seconds.rounded())) s" : "\(Int((seconds / 60).rounded())) min"
    }

    /// The label of a mean-maximal-power duration: 5 -> "5 s", 60 -> "1 min", 1200 -> "20 min", 3600 -> "1 h".
    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 {
            return seconds % 60 == 0 ? "\(seconds / 60) min" : String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        if seconds % 3600 == 0 { return "\(seconds / 3600) h" }
        return String(format: "%d:%02d h", seconds / 3600, (seconds % 3600) / 60)
    }

    /// +3 %, \u{2212}2 %, 0 %. Neutral: no colour is chosen from the sign.
    static func signedPercent(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded == 0 { return "0 %" }
        return (rounded < 0 ? "\u{2212}" : "+") + "\(abs(rounded)) %"
    }

    /// One decimal place or two, trimmed of nothing: 0.83 -> "0.83".
    static func twoDecimals(_ value: Double) -> String { String(format: "%.2f", value) }
}

// MARK: - Zones

enum PFRideZones {
    /// Each zone's share of the ride, 0 to 1, in the order given. Taken from the seconds when there are any,
    /// else from the server's percentages.
    static func fractions(_ zones: [PFRideZone]) -> [Double] {
        let seconds = zones.map { max(0, $0.secs) }
        let totalSeconds = seconds.reduce(0, +)
        if totalSeconds > 0 { return seconds.map { $0 / totalSeconds } }
        let percents = zones.map { max(0, $0.pct ?? 0) }
        let totalPercent = percents.reduce(0, +)
        guard totalPercent > 0 else { return zones.map { _ in 0 } }
        return percents.map { $0 / totalPercent }
    }
}

// MARK: - Chart data

struct PFRidePoint: Equatable {
    var t: Double
    var v: Double?
}

enum PFRideChart {
    /// The chart never draws more points than this, whatever the length of the ride.
    static let maxPoints = 600

    /// At most `maxPoints` points: when there are more samples, the mean of each equal bucket of them. A
    /// bucket with no reading at all stays a gap (nil), so a hole in the stream is never bridged.
    static func downsample(t: [Double], values: [Double?], maxPoints: Int = PFRideChart.maxPoints) -> [PFRidePoint] {
        let n = min(t.count, values.count)
        guard n > 0, maxPoints > 0 else { return [] }
        if n <= maxPoints { return (0..<n).map { PFRidePoint(t: t[$0], v: values[$0]) } }
        let bucket = Int((Double(n) / Double(maxPoints)).rounded(.up))
        var out: [PFRidePoint] = []
        out.reserveCapacity(n / bucket + 1)
        var start = 0
        while start < n {
            let end = min(n, start + bucket)
            var timeSum = 0.0
            var sum = 0.0
            var count = 0
            for index in start..<end {
                timeSum += t[index]
                if let value = values[index] {
                    sum += value
                    count += 1
                }
            }
            out.append(PFRidePoint(t: timeSum / Double(end - start), v: count > 0 ? sum / Double(count) : nil))
            start = end
        }
        return out
    }

    /// The points split into drawable runs: a run ends at a missing reading, at a point inside a pause, and
    /// where two neighbouring points have a pause between them.
    static func runs(_ points: [PFRidePoint], pauses: [PFRidePause]) -> [[PFRidePoint]] {
        var out: [[PFRidePoint]] = []
        var current: [PFRidePoint] = []
        func flush() {
            if !current.isEmpty { out.append(current) }
            current = []
        }
        for point in points {
            guard point.v != nil, !pauses.contains(where: { point.t >= $0.start && point.t < $0.end }) else {
                flush()
                continue
            }
            if let last = current.last, pauses.contains(where: { last.t < $0.start && point.t > $0.start }) { flush() }
            current.append(point)
        }
        flush()
        return out
    }

    /// The value range to draw: from zero for power, tight with a margin for heart rate. nil with no reading.
    static func bounds(_ values: [Double?], zeroBased: Bool) -> ClosedRange<Double>? {
        let present = values.compactMap { $0 }
        guard let low = present.min(), let high = present.max() else { return nil }
        if zeroBased { return 0...max(high, 1) }
        let margin = max((high - low) * 0.1, 2)
        return (low - margin)...(high + margin)
    }
}

/// Everything the ride chart draws, downsampled once when the stream arrives.
struct PFRideChartData {
    var duration: Double
    var power: [PFRidePoint]
    var hr: [PFRidePoint]
    var cadence: [PFRidePoint]
    var target: [PFRidePoint]
    var hasPower: Bool
    var hasHr: Bool
    var hasCadence: Bool
    var hasTarget: Bool
    var pauses: [PFRidePause]

    init(_ stream: PFRideStream, maxPoints: Int = PFRideChart.maxPoints) {
        duration = stream.duration
        power = PFRideChart.downsample(t: stream.t, values: stream.power, maxPoints: maxPoints)
        hr = PFRideChart.downsample(t: stream.t, values: stream.hr, maxPoints: maxPoints)
        cadence = PFRideChart.downsample(t: stream.t, values: stream.cadence, maxPoints: maxPoints)
        target = PFRideChart.downsample(t: stream.t, values: stream.targetPower, maxPoints: maxPoints)
        hasPower = stream.hasPower
        hasHr = stream.hasHr
        hasCadence = stream.hasCadence
        hasTarget = stream.hasTarget
        pauses = stream.pauses
    }

    var hasAnySeries: Bool { hasPower || hasHr || hasCadence }
}

// MARK: - Parsing

enum PFRideParse {

    // MARK: ride-metrics.json

    /// Every ride in the document, newest first. A missing document or a document with no rides gives [].
    static func metrics(_ j: PFJ) -> [PFRide] {
        let rides = j["rides"].dict
        return rides.compactMap { key, value in ride(key: key, value) }
            .sorted { ($0.dateKey, $0.id) > ($1.dateKey, $1.id) }
    }

    static func ride(key: String, _ r: PFJ) -> PFRide? {
        guard r.exists, r.raw is [String: Any] else { return nil }
        let id = r["ride_id"].text ?? key
        let prefix = "bike:"
        let dateKey: String
        if key.hasPrefix(prefix) {
            dateKey = String(key.dropFirst(prefix.count))
        } else if id.hasPrefix(prefix) {
            dateKey = String(id.dropFirst(prefix.count))
        } else {
            dateKey = r["date"].text ?? key
        }
        guard dateKey.count >= 10 else { return nil }
        var out = PFRide(id: id, dateKey: dateKey)
        out.workout = r["workout"].text
        out.resolution = r["resolution"].text
        if let flag = r["stream"].bool { out.hasStream = flag }
        out.samples = r["samples"].int
        out.ftp = r["ftp"].double
        out.durationS = r["duration_s"].double
        out.avgPower = r["avg_power"].double
        out.np = r["np"].double
        out.intensityFactor = r["if"].double
        out.tss = r["tss"].double
        out.vi = r["vi"].double
        out.kj = r["kj"].double
        out.kcalEstimate = r["kcal_est"].double
        out.avgHr = r["avg_hr"].double
        out.ef = r["ef"].double
        let d = r["decoupling"]
        if d.exists {
            out.decoupling = PFRideDecoupling(pct: d["pct"].double, valid: d["valid"].bool, hrDriftBpm: d["hr_drift_bpm"].double)
        }
        out.powerZones = r["power_zones"].array.compactMap { zone($0, lowKey: "lo_w", highKey: "hi_w") }
        out.hrZones = r["hr_zones"].array.compactMap { zone($0, lowKey: "low", highKey: "high") }
        out.mmp = r["mmp"].dict.compactMap { key, value in
            guard let seconds = Int(key), let watts = value.double else { return nil }
            return PFRideMMP(seconds: seconds, watts: watts)
        }.sorted { $0.seconds < $1.seconds }
        out.laps = r["laps"].array.compactMap(lap)
        out.compliance = complianceText(r["compliance"])
        out.hrr1 = r["hrr1"]
        out.type = r["type"].text
        out.summaryLine = r["summary_line"].text
        return out
    }

    private static func zone(_ z: PFJ, lowKey: String, highKey: String) -> PFRideZone? {
        guard let number = z["zone"].int else { return nil }
        return PFRideZone(zone: number, name: z["name"].text, low: z[lowKey].double, high: z[highKey].double,
                          secs: z["secs"].double ?? 0, pct: z["pct"].double)
    }

    private static func lap(_ l: PFJ) -> PFRideLap? {
        guard let n = l["n"].int else { return nil }
        return PFRideLap(n: n, name: l["name"].text, startS: l["start_s"].double, endS: l["end_s"].double,
                         secs: l["secs"].double, avgPower: l["avg_power"].double, pctFtp: l["pct_ftp"].double,
                         targetPower: l["target_power"].double, vsTargetPct: l["vs_target_pct"].double,
                         avgHr: l["avg_hr"].double)
    }

    /// `compliance` arrives as a sentence or as an object carrying one.
    static func complianceText(_ c: PFJ) -> String? {
        if let text = c.text { return text }
        for key in ["text", "summary", "label", "note", "status"] {
            if let text = c[key].text { return text }
        }
        return nil
    }

    // MARK: Stream

    static func stream(_ j: PFJ) -> PFRideStream? {
        guard j.exists, j.raw is [String: Any] else { return nil }
        var out = PFRideStream()
        out.hz = j["hz"].double
        out.rideId = j["ride_id"].text
        out.startMs = j["start_ms"].double
        out.workout = j["workout"].text
        out.ftp = j["ftp"].double
        let step = 1.0 / max(out.hz ?? 1, 0.0001)
        let power = series(j["power"]), hr = series(j["hr"]), cadence = series(j["cadence"])
        let speed = series(j["speed"]), distance = series(j["distance_m"]), target = series(j["target_power"])
        let rawT = series(j["t"])
        let count = max(rawT.count, power.count, hr.count, cadence.count, target.count)
        guard count > 0 else { return nil }
        out.t = (0..<count).map { index in (index < rawT.count ? rawT[index] : nil) ?? Double(index) * step }
        out.power = pad(power, to: count)
        out.hr = pad(hr, to: count)
        out.cadence = pad(cadence, to: count)
        out.speed = pad(speed, to: count)
        out.distanceM = pad(distance, to: count)
        out.targetPower = pad(target, to: count)
        out.laps = j["laps"].array.compactMap(lap)
        out.pauses = j["pauses"].array.compactMap(pause)
        return out
    }

    private static func series(_ j: PFJ) -> [Double?] { j.array.map { $0.double } }

    private static func pad(_ values: [Double?], to count: Int) -> [Double?] {
        values.count >= count ? Array(values.prefix(count)) : values + Array(repeating: nil, count: count - values.count)
    }

    /// A pause is `{start_s, end_s}` (or start / end, or a start and a duration), or a `[start, end]` pair.
    private static func pause(_ p: PFJ) -> PFRidePause? {
        if let start = p[0].double, let end = p[1].double { return end > start ? PFRidePause(start: start, end: end) : nil }
        let start = p["start_s"].double ?? p["start"].double ?? p["from"].double
        var end = p["end_s"].double ?? p["end"].double ?? p["to"].double
        if end == nil, let start, let length = p["duration_s"].double ?? p["secs"].double { end = start + length }
        guard let from = start, let to = end, to > from else { return nil }
        return PFRidePause(start: from, end: to)
    }

    // MARK: day-events.json

    /// The day-event rows that are rides: a workout with a ride id and no Garmin activity.
    static func dayRideEvents(_ j: PFJ) -> [PFRideEvent] {
        j["events"].array.compactMap { e in
            guard e["kind"].text == "workout", let rideId = e["ride_id"].idString,
                  e["activity_id"].idString == nil, let date = e["date"].text else { return nil }
            let timed = !(e["all_day"].bool ?? false)
            var out = PFRideEvent(rideId: rideId, date: String(date.prefix(10)))
            out.startTs = timed ? PFStamp.parse(e["start"].text).map { Int($0.timeIntervalSince1970) } : nil
            out.endTs = timed ? PFStamp.parse(e["end"].text).map { Int($0.timeIntervalSince1970) } : nil
            out.title = e["title"].text
            out.avgPower = e["avg_power"].double
            out.np = e["np"].double
            out.tss = e["tss"].double
            out.avgHr = e["avg_hr"].double
            out.durationMin = e["duration_min"].double
            return out
        }
    }
}
