import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Immutable operation-independent intersections, bound to their complete exact source snapshot.
public struct PreparedBooleanIntersection: Sendable {
    public let targetBodyIDs: [BodyID]
    public let toolBodyID: BodyID
    public let tolerance: ModelingTolerance
    public let sourceTolerance: ModelingTolerance
    public let policy: BooleanPreparationPolicy
    public let diagnostics: BooleanPreparationDiagnostics
    public let intersectionGraph: BooleanIntersectionGraph
    public let uvSplitGraph: BooleanUVSplitGraph
    let model: BRepModel
    let pipeline: BooleanPipeline
    let lifetime: PreparedBooleanQueryLifetime

    init(targetBodyIDs: [BodyID], toolBodyID: BodyID, tolerance: ModelingTolerance,
         sourceTolerance: ModelingTolerance, policy: BooleanPreparationPolicy,
         model: BRepModel, pipeline: BooleanPipeline, intersectionGraph: BooleanIntersectionGraph,
         uvSplitGraph: BooleanUVSplitGraph, lifetime: PreparedBooleanQueryLifetime) {
        self.targetBodyIDs = targetBodyIDs
        self.toolBodyID = toolBodyID
        self.tolerance = tolerance
        self.sourceTolerance = sourceTolerance
        self.policy = policy
        diagnostics = BooleanPreparationDiagnostics(inputBodyCount: targetBodyIDs.count + 1,
            graph: intersectionGraph, split: uvSplitGraph, sourceTolerance: sourceTolerance,
            effectiveTolerance: tolerance, policy: policy)
        self.model = model
        self.pipeline = pipeline
        self.lifetime = lifetime
        self.intersectionGraph = intersectionGraph
        self.uvSplitGraph = uvSplitGraph
    }

    func validateBinding(model: BRepModel, targetBodyIDs: [BodyID], toolBodyID: BodyID,
                         tolerance: ModelingTolerance, owner: BooleanPreparationOwner) throws {
        guard pipeline.preparationOwner === owner,
              self.model == model, self.targetBodyIDs == targetBodyIDs,
              self.toolBodyID == toolBodyID, self.tolerance == tolerance else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "Prepared Boolean intersections do not belong to this configured owner, source snapshot, operands or tolerance.")
        }
    }

    /// Evaluates the retained original graph under its existing cumulative owner.
    public func evaluate(operation: BooleanOperation, keepTools: Bool = false, featureID: FeatureID,
                         subshapes: [SubshapeID: TopologyReference],
                         toolSubshapes: [SubshapeID: TopologyReference] = [:],
                         inputLineage: [SubshapeID: TopologyLineage] = [:],
                         materials: BooleanMaterials = .default) throws -> EvaluationResult {
        var execution = try lifetime.execution()
        return try evaluate(operation: operation, keepTools: keepTools, featureID: featureID,
            subshapes: subshapes, toolSubshapes: toolSubshapes, inputLineage: inputLineage,
            materials: materials, using: &execution)
    }

    public func evaluate(operation: BooleanOperation, keepTools: Bool = false, featureID: FeatureID,
                         subshapes: [SubshapeID: TopologyReference],
                         toolSubshapes: [SubshapeID: TopologyReference] = [:],
                         inputLineage: [SubshapeID: TopologyLineage] = [:],
                         materials: BooleanMaterials = .default,
                         using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        do {
            return try pipeline.evaluate(operation: operation, targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID, keepTools: keepTools, featureID: featureID, model: model,
                subshapes: subshapes, toolSubshapes: toolSubshapes, inputLineage: inputLineage,
                materials: materials, tolerance: tolerance, prepared: self, using: &execution)
        } catch {
            throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
        }
    }

    /// Classifies and selects material regions without recomputing geometric intersections.
    public func selectedRegions(operation: BooleanOperation,
                                materials: BooleanMaterials = .default) throws -> BooleanRegionSelectionGraph {
        var execution = try lifetime.execution()
        return try selectedRegions(operation: operation, materials: materials, using: &execution)
    }

    public func selectedRegions(operation: BooleanOperation,
                                materials: BooleanMaterials = .default,
                                using execution: inout OriginalQueryExecution) throws -> BooleanRegionSelectionGraph {
        try lifetime.withRead(using: &execution) { execution in
        let operands = BooleanOperandContext(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID,
            solidities: try BooleanOperandSolidities.resolve(materials, targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID, model: model, tolerance: tolerance))
        let classification = try pipeline.classificationGraph(uvSplitGraph: uvSplitGraph,
            targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID, model: model,
            operands: operands, tolerance: tolerance, using: &execution)
        let selected = try pipeline.regionSelectionGraph(operation: operation,
            classificationGraph: classification, rule: operands.rule, tolerance: tolerance, using: &execution)
        try CurrentTaskCancellationChecker().checkCancellation()
        try execution.checkpoint()
        return selected
        }
    }

    /// Every dimensional section component with the original face pair and deterministic component ID.
    public var sections: [BooleanSectionComponent] {
        get throws {
            var execution = try lifetime.execution()
            return try sections(using: &execution)
        }
    }

    public func sections(using execution: inout OriginalQueryExecution) throws -> [BooleanSectionComponent] {
        do {
            return try lifetime.withRead(using: &execution) { execution in
            var result: [BooleanSectionComponent] = []
            for split in uvSplitGraph.splits {
                try execution.consumeWork(1)
                for component in split.components {
                    try execution.consumeWork(1)
                    try OriginalParameterQueryStorage.append(BooleanSectionComponent(facePair: split.facePair,
                        componentID: component.id, geometry: component.geometry), to: &result, using: &execution)
                }
            }
            try execution.checkpoint()
            return result
            }
        } catch {
            throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
        }
    }
}
