import CADGeometry
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validateCurrent(evaluated, using: &execution)
    }

    func validateCurrent(_ evaluated: EvaluatedDocument, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try execution.checkpoint()
        // FIXME(INCOMPLETE_IMPLEMENTATION): Drawing freshness still compares the complete
        // authored CADDocument with its retained snapshot. CADIR must supply paid exact
        // structural comparison before this public path has complete bounded source admission.
        guard evaluated.document == document, evaluated.configuration == configuration,
              try OriginalBRepStructuralComparison.models(evaluated.brep, brep, using: &execution) else {
            throw KernelError(phase: .evaluation, code: .missingReference,
                tolerance: configuration.tolerance,
                message: "Drawing geometry belongs to a different original evaluated snapshot.")
        }
    }
}
