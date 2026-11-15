import Foundation

// Build 529 documents (the Plan section): every model in this folder is Foundation only, so the macOS unit-test bundle compiles it too.
// A field the server leaves out or sends as null decodes as nil, and a key the model does not know is ignored. Decode with
// `PFPlan529Decoder.make()`: the documents use snake_case keys.

enum PFPlan529Decoder {
    static func make() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
