import Foundation

/// The newest weight reading Today knows (Apple Health, the scale through PaceForge, ...), with who supplied it and its day.
/// Lives in the shared target because Today (shared with macOS) holds it; Weight vs goal (iOS) reads it.
struct PFNewestWeight: Equatable {
    let kg: Double
    let source: String
    /// yyyy-MM-dd.
    let day: String
}
