import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct ValidatedFeatureEvaluation: Sendable {
    package init(
        validating result: EvaluationResult,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution(budget: OriginalQueryBudget(),
            limits: .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try self.init(validating: result, tolerance: tolerance, using: &execution)
    }

    package init(
        planarExtrusion result: EvaluationResult,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution(budget: OriginalQueryBudget(),
            limits: .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try self.init(planarExtrusion: result, tolerance: tolerance, using: &execution)
    }

    package init(
        importedExact result: EvaluationResult,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution(budget: OriginalQueryBudget(),
            limits: .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try self.init(importedExact: result, featureID: featureID, tolerance: tolerance, using: &execution)
    }

    package let result: EvaluationResult
    package let brep: ValidatedBRepModel

    package init(
        validating result: EvaluationResult,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        let exactResult = try Self.exactResult(result, tolerance: tolerance, using: &execution)
        self.result = exactResult
        brep = try Self.validatedBRep(
            for: exactResult,
            tolerance: tolerance
        , using: &execution)
    }

    package init(
        planarExtrusion result: EvaluationResult,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        let exactResult = try Self.exactResult(result, tolerance: tolerance, using: &execution)
        self.result = exactResult
        brep = try Self.validatedBRep(
            for: exactResult,
            tolerance: tolerance
        , using: &execution)
    }

    package init(
        importedExact result: EvaluationResult,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try FeatureTopologyLineageValidator().validate(result, featureID: featureID, using: &execution)
        try result.brep.validate(level: .exact, tolerance: tolerance, maximumSubdivisionDepth: 32, remainingSourceDepth: 16, using: &execution)
        self.result = result
        brep = try Self.validatedBRep(
            for: result,
            tolerance: tolerance
        , using: &execution)
    }

    private static func exactResult(
        _ result: EvaluationResult,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        try FeatureTopologyLineageValidator().validate(result, using: &execution)
        var exactResult = result
        try ExactFacePcurveBuilder().populateMissingPcurves(
            in: &exactResult.brep,
            tolerance: tolerance
        , using: &execution)
        return exactResult
    }

    private static func validatedBRep(
        for result: EvaluationResult,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> ValidatedBRepModel {
        if let certificate = result.validatedBRep,
           try OriginalBRepStructuralComparison.models(certificate.model, result.brep,
               using: &execution),
           certificate.tolerance == tolerance,
           certificate.validationLevel != .modeling {
            return certificate
        }
        return try ValidatedBRepModel(
            result.brep,
            tolerance: tolerance,
            validationLevel: .exact, maximumSubdivisionDepth: 32, remainingSourceDepth: 16
        , using: &execution)
    }
}
