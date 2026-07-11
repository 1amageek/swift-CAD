import CADCore
import CADIR

struct ValidatedFeatureEvaluation: Sendable {
    let result: EvaluationResult
    let brep: ValidatedBRepModel

    init(
        validating result: EvaluationResult,
        tolerance: ModelingTolerance
    ) throws {
        self.result = result
        brep = try ValidatedBRepModel(result.brep, tolerance: tolerance)
    }

    init(
        planarExtrusion result: EvaluationResult,
        tolerance: ModelingTolerance
    ) throws {
        self.result = result
#if DEBUG
        brep = try ValidatedBRepModel(result.brep, tolerance: tolerance)
#else
        brep = ValidatedBRepModel(
            composingValidatedFeatureResults: result.brep,
            tolerance: tolerance
        )
#endif
    }
}
