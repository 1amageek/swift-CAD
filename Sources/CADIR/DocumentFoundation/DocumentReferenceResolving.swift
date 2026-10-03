import CADCore

public protocol DocumentReferenceResolving: Sendable {
    func resolve(_ reference: DocumentObjectReference,
                 in snapshots: [DocumentID: CADDocument],
                 tolerance: ModelingTolerance) throws -> ResolvedDocumentObject
}
