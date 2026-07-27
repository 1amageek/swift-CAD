import CADCore
import CADIR
import CADTopology

package struct ValidatedFeatureEvaluation: Sendable {
    package let result: EvaluationResult
    package let brep: ValidatedBRepModel

    package init(
        validating result: EvaluationResult,
        tolerance: ModelingTolerance
    ) throws {
        let exactResult = try Self.exactResult(result, tolerance: tolerance)
        self.result = exactResult
        brep = try ValidatedBRepModel(
            exactResult.brep,
            tolerance: tolerance,
            validationLevel: .exact
        )
    }

    package init(
        planarExtrusion result: EvaluationResult,
        tolerance: ModelingTolerance
    ) throws {
        let exactResult = try Self.exactResult(result, tolerance: tolerance)
        self.result = exactResult
        brep = try ValidatedBRepModel(
            exactResult.brep,
            tolerance: tolerance,
            validationLevel: .exact
        )
    }

    private static func exactResult(
        _ result: EvaluationResult,
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult {
        try FeatureTopologyLineageValidator().validate(result)
        var exactResult = result
        try ExactFacePcurveBuilder().populateMissingPcurves(
            in: &exactResult.brep,
            tolerance: tolerance
        )
        return exactResult
    }
}
