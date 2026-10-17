import CADCore

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

    func resolve<A: NumericWorkAdmission & ~Copyable>(using admission: inout A) throws -> CADDocumentSourceFingerprint {
        try admission.checkpoint()
        switch self {
        case .value(let fingerprint):
            try admission.consumeWork(1)
            try admission.retainStorage(count: 1, stride: MemoryLayout<CADDocumentSourceFingerprint>.stride)
            try admission.checkpoint()
            return fingerprint
        case .validatedDocument(let document):
            return try document.sourceFingerprint(using: &admission)
        }
    }

}
