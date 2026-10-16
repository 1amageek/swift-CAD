import HashTreeCollections
import CADCore

public struct DefaultDocumentReferenceResolver: DocumentReferenceResolving {
    public init() {}
    public func resolve(_ reference: DocumentObjectReference,
                        in snapshots: [DocumentID: CADDocument],
                        tolerance: ModelingTolerance) throws -> ResolvedDocumentObject {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard let document = snapshots[reference.documentID] else { throw DocumentFoundationError.missingDocument(reference.documentID) }
        guard document.id == reference.documentID else {
            throw DocumentFoundationError.snapshotIDMismatch(expected: reference.documentID, actual: document.id)
        }
        try document.validate(tolerance: tolerance)
        switch reference.target {
        case .document: return .document(document)
        case .feature(let id):
            guard let feature = document.designGraph.nodes[id] else { throw DocumentFoundationError.missingTarget(reference) }
            return .feature(feature)
        case .parameter(let id):
            guard let parameter = document.parameters.parameters[id] else { throw DocumentFoundationError.missingTarget(reference) }
            return .parameter(parameter)
        case .attribute(let id):
            guard let attribute = document.documentFoundation.attribute(id: id) else { throw DocumentFoundationError.missingTarget(reference) }
            return .attribute(attribute)
        }
    }
}
