import SwiftUI
import ImageIO

/// Shrinks a picked photo for upload: 1600 px on the long edge (never enlarged), JPEG quality 0.8. The shrinking is the avatar picker's
/// own (`AvatarImage`, ImageIO, honours the photo's orientation).
enum PFPhotoPrep {
    static func jpeg(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let edge = PFPhotoSize.longEdge(width: width, height: height)
        return AvatarImage.downscaledJPEG(from: data, maxDimension: CGFloat(edge), quality: CGFloat(PFPhotoSize.jpegQuality))
    }
}

/// One workout photo from the picker to PaceForge's reading of it: upload, follow the job, read the draft. Nothing is asked of the
/// athlete in between: the photo is a rough idea for the assessment.
@MainActor
final class PFPhotoFlow: ObservableObject {
    @Published private(set) var stage: PFPhotoStage = .idle

    /// Whether the picker should be offered: not while a photo is on its way.
    var isBusy: Bool { stage == .sending || stage == .reading }

    func upload(_ picked: Data, activityID: String?, date: String?) async {
        guard !isBusy else { return }
        stage = .sending
        let prepared = await Task.detached(priority: .userInitiated) { PFPhotoPrep.jpeg(from: picked) }.value
        guard let jpeg = prepared else {
            stage = .failed("That photo could not be opened.")
            return
        }
        let photoID = PFJobInputs.newPhotoID()
        let inputs = PFJobInputs.analyzeWorkoutPhoto(photoID: photoID, imageBase64: jpeg.base64EncodedString(),
                                                     activityID: activityID, date: date)
        switch await PFJobClient.submit(.analyzeWorkoutPhoto, inputs: inputs) {
        case .failure(let failure):
            stage = .failed(failure.message)
        case .success(let submission):
            stage = .reading
            if !submission.state.isFinished,
               case .failure(let failure) = await PFJobClient.wait(for: submission.id, job: .analyzeWorkoutPhoto) {
                stage = .failed(failure.message)
                return
            }
            stage = await readDraft(photoID)
        }
    }

    /// An earlier photo of this session that PaceForge is still trying to read, or gave up on (`photos/pending.json`).
    func checkEarlier(activityID: String?, date: String?) async {
        guard stage == .idle, let key = PFPhotoPending.key(activityID: activityID, date: date) else { return }
        let data = await PFAPI.fetchOptional("data/photos/pending.json")
        if stage == .idle, let earlier = PFPhotoPending.stage(from: data, key: key) { stage = earlier }
    }

    /// The draft is written by the time the job is done; a short wait covers the file not being served yet.
    private func readDraft(_ photoID: String) async -> PFPhotoStage {
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            let data = await PFAPI.fetchOptional("data/photos/\(photoID).json")
            let reached = PFPhotoDraft.stage(from: data)
            if reached != .reading { return reached }
        }
        return .failed("PaceForge has your photo, but its reading is not in yet. Check again later.")
    }
}
