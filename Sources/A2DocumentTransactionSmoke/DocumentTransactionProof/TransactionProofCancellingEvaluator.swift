import SwiftCAD

struct TransactionProofCancellingEvaluator: ExactDocumentEvaluating {
    var evaluationTolerance: ModelingTolerance { .standard }

    func evaluateExact(_ document: CADDocument) throws -> EvaluatedDocument {
        let actual = try DocumentEvaluator(tolerance: .standard).evaluateExact(document)
        if document.documentFoundation.attributes.contains(where: { $0.name == "cancelAfterEvaluation" }) {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return actual
    }
}
