import Foundation

/// The UI-test fixture with the build-529 documents merged in. `PaceForgeFixture.json` is the big fixture (served path -> document, plus
/// "today"); every `Fixtures529/*.json` is one more such object. A stream adds its documents by adding a file there, without touching the
/// big fixture or any test. A path both define is merged one level deep when both are objects (a file can add `short` to a report), and
/// replaced otherwise.
enum Fixtures529 {
    private final class BundleToken {}

    static let folder = "Fixtures529"

    /// The fixture text `PF_FIXTURE_JSON` carries: the big fixture's bytes with every merged file, in file-name order.
    static func merged(_ base: Data) throws -> String {
        let bundle = Bundle(for: BundleToken.self)
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: folder) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else { return String(decoding: base, as: UTF8.self) }
        guard var files = try JSONSerialization.jsonObject(with: base) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for url in urls {
            guard let extra = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            for (path, document) in extra {
                if var old = files[path] as? [String: Any], let new = document as? [String: Any] {
                    old.merge(new) { _, added in added }
                    files[path] = old
                } else {
                    files[path] = document
                }
            }
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: files), as: UTF8.self)
    }
}
