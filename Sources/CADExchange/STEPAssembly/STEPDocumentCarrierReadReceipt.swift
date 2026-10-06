import CADCore

/// Accounting transferred only after the actual framing profile is admitted.
struct STEPDocumentCarrierReadReceipt {
    let documentID: DocumentID
    let documentName: String
    let consumedEntities: Int
    let consumedWork: Int
    let consumedTextBytes: Int
}
