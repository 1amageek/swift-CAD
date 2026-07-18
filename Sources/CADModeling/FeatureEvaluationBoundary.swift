import CADCore
import CADIR
import CADTopology

package enum FeatureEvaluationBoundary {
    package static func evaluateValidated(
        featureID: FeatureID,
        tolerance: ModelingTolerance,
        operation: () throws -> EvaluationResult
    ) throws -> ValidatedFeatureEvaluation {
        do {
            try tolerance.validate()
            let result = try operation()
            return try ValidatedFeatureEvaluation(
                validating: result,
                tolerance: tolerance
            )
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .evaluation,
                featureID: featureID,
                tolerance: tolerance
            )
        }
    }

    package static func evaluate(
        featureID: FeatureID,
        tolerance: ModelingTolerance,
        operation: () throws -> EvaluationResult
    ) throws -> EvaluationResult {
        do {
            return try operation()
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .evaluation,
                featureID: featureID,
                tolerance: tolerance
            )
        }
    }

    package static func validateRequest(
        featureID: FeatureID,
        tolerance: ModelingTolerance,
        validation: () throws -> Void
    ) throws {
        do {
            try validation()
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .validation,
                featureID: featureID,
                tolerance: tolerance
            )
        }
    }

    package static func validateExactInput(
        _ model: BRepModel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws {
        do {
            try model.validate(level: .exact, tolerance: tolerance)
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .topology,
                featureID: featureID,
                tolerance: tolerance
            )
        }
    }
}
