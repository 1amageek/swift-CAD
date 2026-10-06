import CADCore
import CADIR
import CADTopology

/// One immutable source authority shared by the drawing results of an invocation.
final class BRepDrawingSourceSnapshot: Sendable {
    private let document: CADDocument
    private let configuration: DocumentEvaluationConfiguration
    private let brep: BRepModel

    init(_ evaluated: EvaluatedDocument) {
        document = evaluated.document
        configuration = evaluated.configuration
        brep = evaluated.brep
    }

    func validateCurrent(_ evaluated: EvaluatedDocument) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard evaluated.document == document, evaluated.configuration == configuration,
              evaluated.brep == brep else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: configuration.tolerance,
                message: "Drawing geometry belongs to a different original evaluated snapshot.")
        }
    }
}
