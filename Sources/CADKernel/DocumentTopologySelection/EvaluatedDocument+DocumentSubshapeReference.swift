import CADCore
import CADIR

extension EvaluatedDocument {
    /// Resolves a persisted source witness against this supplied current evaluated snapshot.
    public func topologyReferences(forDocumentAttribute id: DocumentAttributeID) throws -> [TopologyReference] {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard let attribute = document.documentFoundation.attribute(id: id) else {
            throw DocumentFoundationError.missingAttribute(id)
        }
        let references: [StableSubshapeReference]
        switch attribute.value {
        case .subshapeReference(let reference): references = [reference]
        case .subshapeReferences(let values): references = values
        default:
            throw DocumentFoundationError.invalidValue("The requested attribute does not contain stable subshape witnesses.")
        }
        var result: [TopologyReference] = []
        for reference in references {
            try CurrentTaskCancellationChecker().checkCancellation()
            result.append(try topologyReference(for: reference))
        }
        return result
    }
}
