import CADCore
import CADIR

/// Evaluates the exact document state without materializing derived artifacts.
///
/// Planning, selection, and geometric query services depend on this boundary
/// because meshes are outputs of exact evaluation, not inputs to those
/// decisions.
public protocol ExactDocumentEvaluating: Sendable {
    var evaluationTolerance: ModelingTolerance { get }

    func evaluateExact(_ document: CADDocument) throws -> EvaluatedDocument
}
