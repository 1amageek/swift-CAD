/// A cache's record of the source fingerprint it was made from: the value itself, or the
/// validated document it is the fingerprint of.
///
/// An evaluation records the validated document it evaluated, and the fingerprint is hashed only
/// when something first reads it; `ValidatedCADDocument` computes its fingerprint at most once,
/// so every cache of one evaluation shares that one hash.
package enum CacheSourceFingerprint: Sendable {
    case value(CADDocumentSourceFingerprint)
    case validatedDocument(ValidatedCADDocument)

    func resolve() throws -> CADDocumentSourceFingerprint {
        switch self {
        case .value(let fingerprint):
            fingerprint
        case .validatedDocument(let document):
            try document.sourceFingerprint()
        }
    }
}
