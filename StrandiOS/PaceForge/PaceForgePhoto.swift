import Foundation

// A workout photo as the app sees it: the shrink the photo gets before it is sent, and how PaceForge's draft of the reading
// (`data/photos/<photo_id>.json`) and its retry queue (`data/photos/pending.json`) read. Foundation only, so it is compiled into the
// macOS unit-test bundle. The upload itself goes through the job door (PaceForgeJob.swift).

/// Where a workout photo stands, from the app's side.
enum PFPhotoStage: Equatable {
    case idle
    case sending
    case reading
    /// The photo was read; the summary is PaceForge's one-line reading when it gave one.
    case read(String?)
    /// The model was busy; PaceForge tries again on its own.
    case retrying
    case couldNotRead
    case failed(String)
}

enum PFPhotoSize {
    static let maxLongEdge = 1600
    static let jpegQuality = 0.8

    /// The long edge to shrink a photo to: 1600 px, or the photo's own long edge when that is smaller (a photo is never enlarged).
    static func longEdge(width: Int, height: Int) -> Int {
        let long = max(width, height)
        return long <= 0 ? maxLongEdge : min(long, maxLongEdge)
    }
}

/// `data/photos/<photo_id>.json`, the draft the runner writes while and after it reads a photo.
enum PFPhotoDraft {
    /// No file yet reads as still reading. A draft with a `state` (the retry queue's words) follows it; a first read has none: an
    /// `error` with `retrying` is the busy model, an `error` alone is a photo that could not be read, a summary or exercises is a read.
    static func stage(from data: Data?) -> PFPhotoStage {
        guard let data else { return .reading }
        let json = PFJ(data: data)
        guard json.exists else { return .reading }
        switch json["state"].text ?? "" {
        case "retrying": return .retrying
        case "gave_up", "failed": return .couldNotRead
        case "read", "superseded": return .read(summary(json))
        default: break
        }
        if json["retrying"].bool == true { return .retrying }
        if json["error"].text != nil { return .couldNotRead }
        let reading = summary(json)
        if reading != nil || !json["exercises"].array.isEmpty { return .read(reading) }
        return .reading
    }

    /// The reading's one line: its summary, else the first few exercise names.
    static func summary(_ json: PFJ) -> String? {
        if let text = json["summary"].text { return String(text.prefix(300)) }
        let names = json["exercises"].array.compactMap { $0["name"].text }
        return names.isEmpty ? nil : names.prefix(3).joined(separator: ", ")
    }
}

/// `data/photos/pending.json`: the newest photo per activity (or `date:<iso>`) that is being retried or was given up on.
enum PFPhotoPending {
    /// The key the runner files a photo under: the activity id, else `date:<iso>`.
    static func key(activityID: String?, date: String?) -> String? {
        if let id = PFJobInputs.activityID(activityID) { return id }
        if let date, !date.isEmpty { return "date:\(date)" }
        return nil
    }

    /// What an earlier photo of this session stands at; nil when there is none to say (no entry, or one that was read).
    static func stage(from data: Data?, key: String) -> PFPhotoStage? {
        switch PFJ(data: data)[key]["state"].text ?? "" {
        case "retrying": return .retrying
        case "gave_up", "failed": return .couldNotRead
        default: return nil
        }
    }
}
