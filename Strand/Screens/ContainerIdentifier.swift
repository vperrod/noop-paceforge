import SwiftUI

extension View {
    /// Gives a container (a card, a stack) its own accessibility identifier. A bare `.accessibilityIdentifier`
    /// on a container is handed down to every view inside it, replacing the identifiers those views carry
    /// themselves, so a test could no longer find a button by its own name. Making the container a real
    /// accessibility element keeps its identifier on the container and leaves its children's alone.
    func containerIdentifier(_ id: String) -> some View {
        accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }
}
