import CADCore
import CADGeometry
import CADIR
import CADTopology

package enum FeatureEvaluationBoundary {
    package static func evaluateValidated(
        featureID: FeatureID,
        tolerance: ModelingTolerance,
        operation: () throws -> EvaluationResult
    ) throws -> ValidatedFeatureEvaluation {
        var execution = try OriginalQueryExecution(budget: OriginalQueryBudget(),
            limits: .init(maximumValueDepth: 32, maximumCoefficientDepth: 32),
            context: .init(operation: .conversion, entry: .ordinary, stage: .request))
        return try evaluateValidated(featureID: featureID, tolerance: tolerance, using: &execution) { _ in
            try operation()
        }
    }

    package static func evaluateValidated(
        featureID: FeatureID,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution,
        operation: (inout OriginalQueryExecution) throws -> EvaluationResult
    ) throws -> ValidatedFeatureEvaluation {
        do {
            execution.context = execution.context.at(stage: .request)
            try execution.checkpoint()
            try tolerance.validate()
            let result = try operation(&execution)
            execution.context = execution.context.at(stage: .publication)
            let validated = try ValidatedFeatureEvaluation(validating: result,
                tolerance: tolerance, using: &execution)
            try execution.checkpoint()
            return validated
        } catch {
            throw publishedFailure(error, phase: .evaluation, featureID: featureID,
                tolerance: tolerance, context: execution.context)
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
            throw publishedFailure(error, phase: .evaluation, featureID: featureID,
                tolerance: tolerance,
                context: .init(operation: .conversion, entry: .ordinary, stage: .publication))
        }
    }

    package static func validateRequest(
        featureID: FeatureID, tolerance: ModelingTolerance,
        validation: () throws -> Void
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validateRequest(featureID: featureID, tolerance: tolerance, using: &execution) {
            try validation()
        }
    }

    package static func validateRequest(
        featureID: FeatureID, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution,
        validation: () throws -> Void
    ) throws {
        try validateRequest(featureID: featureID, tolerance: tolerance, using: &execution) { _ in
            try validation()
        }
    }

    package static func validateRequest(
        featureID: FeatureID, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution,
        validation: (inout OriginalQueryExecution) throws -> Void
    ) throws {
        do {
            execution.context = execution.context.at(stage: .request)
            try execution.checkpoint()
            try validation(&execution)
        } catch {
            throw publishedFailure(error, phase: .validation, featureID: featureID,
                tolerance: tolerance, context: execution.context)
        }
    }

    package static func validateExactInput(
        _ model: BRepModel, featureID: FeatureID, tolerance: ModelingTolerance
    ) throws {
        var execution = try BRepModel.originalValidationExecution()
        try validateExactInput(model, featureID: featureID, tolerance: tolerance, using: &execution)
    }

    package static func validateExactInput(
        _ model: BRepModel, featureID: FeatureID, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws {
        do {
            execution.context = execution.context.at(stage: .source)
            try execution.consumeWork(1)
            try model.validate(level: .exact, tolerance: tolerance,
                maximumSubdivisionDepth: 32, remainingSourceDepth: 16, using: &execution)
        } catch {
            throw publishedFailure(error, phase: .topology, featureID: featureID,
                tolerance: tolerance, context: execution.context)
        }
    }

    package static func validateExactInput(
        _ context: EvaluationContext, featureID: FeatureID, tolerance: ModelingTolerance
    ) throws {
        var execution = try BRepModel.originalValidationExecution()
        try validateExactInput(context, featureID: featureID, tolerance: tolerance, using: &execution)
    }

    package static func validateExactInput(
        _ context: EvaluationContext, featureID: FeatureID, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        if let validatedBRep = context.validatedBRep,
           try OriginalBRepStructuralComparison.models(validatedBRep.model, context.brep,
               using: &execution),
           validatedBRep.tolerance == tolerance,
           validatedBRep.validationLevel != .modeling { return }
        try validateExactInput(context.brep, featureID: featureID,
            tolerance: tolerance, using: &execution)
    }

    private static func publishedFailure(_ error: any Error, phase: KernelPhase,
        featureID: FeatureID, tolerance: ModelingTolerance,
        context: OriginalQueryFailureContext) -> any Error {
        let published = OriginalQueryFailure.published(error, context: context, tolerance: tolerance)
        let retainedClassification = OriginalQueryFailure.classification(of: published)
        let classification: KernelError
        if let retainedClassification,
           retainedClassification.code == .resourceLimitExceeded || retainedClassification.code == .cancelled {
            classification = KernelError.wrapping(retainedClassification, phase: phase,
                featureID: featureID, tolerance: tolerance)
        } else {
            classification = OriginalQueryFailure.classification(of: error) ?? KernelError.wrapping(error,
                phase: phase, featureID: featureID, tolerance: tolerance)
        }
        return OriginalQueryFailure.contextualizing(published, classification: classification)
    }

}
