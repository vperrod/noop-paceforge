import SwiftUI

/// Fetches one PaceForge document, keeps the last good copy on the phone and decodes it. The Plan section's screens each own one:
///
///     @StateObject private var store = PFDocStore529<PFSeasonDoc>(path: PFDocPath529.season)
///     switch store.state { case .loading: …; case .loaded(let doc): …; case .empty: …; case .failed: … }   // and `.task { await store.refresh() }`
///
/// `.empty` is a document the server does not serve (or one `isEmpty` calls empty); `.failed` is a server that could not be asked with no
/// saved copy to show. When the server cannot be asked but a copy is saved, the copy is `.loaded` and `isStale` is true.
@MainActor
final class PFDocStore529<Doc: Decodable & Equatable>: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(Doc)
        case empty
        case failed
    }

    @Published private(set) var state: State = .loading
    /// The shown document is the saved copy because the server could not be asked.
    @Published private(set) var isStale = false

    let path: String
    private let isEmpty: (Doc) -> Bool
    private var lastFetch: Date?
    private var inFlight: Task<Void, Never>?

    /// `showsSavedFirst`: the copy saved on the phone is the first thing on screen, so the first frame never waits for the network; the
    /// server is asked right after and its answer replaces it. Nothing is shown when there is no saved copy (or it does not read).
    init(path: String, showsSavedFirst: Bool = false, isEmpty: @escaping (Doc) -> Bool = { _ in false }) {
        self.path = path
        self.isEmpty = isEmpty
        if showsSavedFirst { showSaved() }
    }

    private func showSaved() {
        guard PFAPI.usesPhoneState, let data = PFStore.read(path: path),
              let parsed = try? PFPlan529Decoder.make().decode(Doc.self, from: data), !isEmpty(parsed) else { return }
        state = .loaded(parsed)
    }

    var doc: Doc? {
        if case .loaded(let doc) = state { return doc }
        return nil
    }

    /// Loads again unless the last good load is under `maxAge` seconds old.
    func refreshIfStale(maxAge: TimeInterval = 60) async {
        if let lastFetch, doc != nil, !isStale, Date().timeIntervalSince(lastFetch) < maxAge { return }
        await refresh()
    }

    /// Overlapping callers share the load already running.
    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { [self] in
            await load()
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    private func load() async {
        guard PFAPI.isConfigured else {
            state = .empty
            return
        }
        let fetched = await PFAPI.fetchDoc(path)
        guard let data = fetched.data else {
            // Not served: nothing to show. Not asked: keep what is on screen, else report the failure.
            if !fetched.failed { state = .empty } else if doc == nil { state = .failed }
            isStale = fetched.failed && doc != nil
            return
        }
        guard let parsed = try? PFPlan529Decoder.make().decode(Doc.self, from: data) else {
            if doc == nil { state = .failed }
            return
        }
        state = isEmpty(parsed) ? .empty : .loaded(parsed)
        isStale = fetched.failed
        if !fetched.failed { lastFetch = Date() }
    }
}
