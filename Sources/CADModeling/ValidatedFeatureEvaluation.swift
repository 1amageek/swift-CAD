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
        brep = try Self.validatedBRep(
            for: exactResult,
            tolerance: tolerance
        )
    }

    package init(
        planarExtrusion result: EvaluationResult,
        tolerance: ModelingTolerance
    ) throws {
        let exactResult = try Self.exactResult(result, tolerance: tolerance)
        self.result = exactResult
        brep = try Self.validatedBRep(
            for: exactResult,
            tolerance: tolerance
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

    private static func validatedBRep(
        for result: EvaluationResult,
        tolerance: ModelingTolerance
    ) throws -> ValidatedBRepModel {
        if let certificate = result.validatedBRep,
           certificate.model == result.brep,
           certificate.tolerance == tolerance,
           certificate.validationLevel != .modeling {
            return certificate
        }
        return try ValidatedBRepModel(
            result.brep,
            tolerance: tolerance,
            validationLevel: .exact
        )
    }
}
