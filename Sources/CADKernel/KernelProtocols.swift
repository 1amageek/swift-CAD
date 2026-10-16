import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

public protocol SketchProfileExtracting: Sendable {
    func extractProfiles(
        from sketch: Sketch,
        sourceFeatureID: FeatureID,
        parameters: ResolvedParameterTable
    ) throws -> [Profile]
}

public protocol SketchCurveExtracting: Sendable {
    func extractCurves(
        from sketch: Sketch,
        sourceFeatureID: FeatureID,
        parameters: ResolvedParameterTable
    ) throws -> [EvaluatedCurve]
}

public protocol BRepBooleanEvaluating: Sendable {
    func intersectionRequirement(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ) throws -> BooleanIntersectionRequirement

    func exactRegionSelection(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        uvSplitGraph: BooleanUVSplitGraph,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ) throws -> BooleanExactRegionSelectionGraph

    func evaluate(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        keepTools: Bool,
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        toolSubshapes: [SubshapeID: TopologyReference],
        intersectionGraph: BooleanIntersectionGraph,
        uvSplitGraph: BooleanUVSplitGraph,
        classificationGraph: BooleanClassificationGraph,
        exactRegionSelectionGraph: BooleanExactRegionSelectionGraph,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult
    func intersectionRequirement(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> BooleanIntersectionRequirement
    func exactRegionSelection(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        uvSplitGraph: BooleanUVSplitGraph,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> BooleanExactRegionSelectionGraph
    func evaluate(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        keepTools: Bool,
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        toolSubshapes: [SubshapeID: TopologyReference],
        intersectionGraph: BooleanIntersectionGraph,
        uvSplitGraph: BooleanUVSplitGraph,
        classificationGraph: BooleanClassificationGraph,
        exactRegionSelectionGraph: BooleanExactRegionSelectionGraph,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> EvaluationResult
}

public extension BRepBooleanEvaluating {
    func intersectionRequirement(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ) throws -> BooleanIntersectionRequirement {
        .required
    }
    func intersectionRequirement(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> BooleanIntersectionRequirement {
        try execution.consumeWork(1)
        return .required
    }
    func exactRegionSelection(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        uvSplitGraph: BooleanUVSplitGraph,
        regionSelectionGraph: BooleanRegionSelectionGraph,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> BooleanExactRegionSelectionGraph {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Injected Boolean providers must retain
        // the original execution through materialization and final publication.
        throw KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
            message: "The injected Boolean provider lacks direct execution.")
    }
    func evaluate(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        keepTools: Bool,
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        toolSubshapes: [SubshapeID: TopologyReference],
        intersectionGraph: BooleanIntersectionGraph,
        uvSplitGraph: BooleanUVSplitGraph,
        classificationGraph: BooleanClassificationGraph,
        exactRegionSelectionGraph: BooleanExactRegionSelectionGraph,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> EvaluationResult {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Injected Boolean providers must retain
        // the original execution through materialization and final publication.
        throw KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
            message: "The injected Boolean provider lacks direct execution.")
    }
}

public protocol Tessellating: Sendable {
    func tessellate(model: BRepModel, options: TessellationOptions) throws -> [BodyID: Mesh]
    func tessellate(model: BRepModel, options: TessellationOptions,
        using execution: inout OriginalQueryExecution) throws -> [BodyID: Mesh]
    func tessellate(validatedModel: ValidatedBRepModel, options: TessellationOptions,
        using execution: inout OriginalQueryExecution) throws -> [BodyID: Mesh]
    func tessellate(validatedModel: ValidatedBRepModel, options: TessellationOptions,
        limits: TessellationLimits, reserving: TessellationUsage,
        using execution: inout OriginalQueryExecution) throws -> [BodyID: Mesh]
    func tessellate(
        validatedModel: ValidatedBRepModel,
        options: TessellationOptions
    ) throws -> [BodyID: Mesh]

    /// Tessellates a validated model under a request-specific ceiling while
    /// reserving usage already retained by the caller.
    ///
    /// The default implementation validates the request and dispatches to the
    /// existing requirement. Legacy conformers therefore remain source
    /// compatible, while the evaluator's final aggregate guard still protects
    /// callers whose old implementation cannot enforce the reservation before
    /// allocating output.
    func tessellate(
        validatedModel: ValidatedBRepModel,
        options: TessellationOptions,
        limits: TessellationLimits,
        reserving: TessellationUsage
    ) throws -> [BodyID: Mesh]
}

public extension Tessellating {
    // FIXME(INCOMPLETE_IMPLEMENTATION): A conformer without a direct witness
    // reaches this failure through caller-execution Tessellating consumers.
    // It must implement the same-execution algorithm before returning success.
    func tessellate(model: BRepModel, options: TessellationOptions,
        using execution: inout OriginalQueryExecution) throws -> [BodyID: Mesh] {
        try execution.checkpoint()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: nil,
            message: "Tessellator does not implement caller-execution tessellation.")
    }

    func tessellate(validatedModel: ValidatedBRepModel, options: TessellationOptions,
        using execution: inout OriginalQueryExecution) throws -> [BodyID: Mesh] {
        try tessellate(model: validatedModel.model, options: options, using: &execution)
    }

    func tessellate(validatedModel: ValidatedBRepModel, options: TessellationOptions,
        limits: TessellationLimits, reserving: TessellationUsage,
        using execution: inout OriginalQueryExecution) throws -> [BodyID: Mesh] {
        try execution.checkpoint(); try limits.validate(); try reserving.validate()
        if let exceeded = reserving.firstResourceExceeding(limits) {
            throw TessellationError.resourceExhausted(exceeded,
                requested: reserving.amount(for: exceeded), limit: limits.limit(for: exceeded))
        }
        return try tessellate(validatedModel: validatedModel, options: options, using: &execution)
    }

    func tessellate(
        validatedModel: ValidatedBRepModel,
        options: TessellationOptions
    ) throws -> [BodyID: Mesh] {
        try tessellate(model: validatedModel.model, options: options)
    }

    func tessellate(
        validatedModel: ValidatedBRepModel,
        options: TessellationOptions,
        limits: TessellationLimits,
        reserving: TessellationUsage
    ) throws -> [BodyID: Mesh] {
        try limits.validate()
        try reserving.validate()
        if let exceeded = reserving.firstResourceExceeding(limits) {
            throw TessellationError.resourceExhausted(
                exceeded,
                requested: reserving.amount(for: exceeded),
                limit: limits.limit(for: exceeded)
            )
        }
        return try tessellate(validatedModel: validatedModel, options: options)
    }
}
