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

    init(targetBodyIDs: [BodyID], toolBodyID: BodyID, tolerance: ModelingTolerance,
         sourceTolerance: ModelingTolerance, policy: BooleanPreparationPolicy,
         model: BRepModel, pipeline: BooleanPipeline, intersectionGraph: BooleanIntersectionGraph,
         uvSplitGraph: BooleanUVSplitGraph) {
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

    /// `lineageAdmission` borrows a history-phase allowance only; other Boolean
    /// phases and physical allocator retention are not covered by this argument.
    public func evaluate(operation: BooleanOperation, keepTools: Bool = false, featureID: FeatureID,
                         subshapes: [SubshapeID: TopologyReference],
                         toolSubshapes: [SubshapeID: TopologyReference] = [:],
                         inputLineage: [SubshapeID: TopologyLineage] = [:],
                         materials: BooleanMaterials = .default,
                         lineageAdmission: GeometryConversionAdmission? = nil) throws -> EvaluationResult {
        try pipeline.evaluate(operation: operation, targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID,
            keepTools: keepTools, featureID: featureID, model: model, subshapes: subshapes,
            toolSubshapes: toolSubshapes, inputLineage: inputLineage, materials: materials,
            tolerance: tolerance, prepared: self, lineageAdmission: lineageAdmission)
    }

    /// Classifies and selects material regions without recomputing geometric intersections.
    public func selectedRegions(operation: BooleanOperation,
                                materials: BooleanMaterials = .default) throws -> BooleanRegionSelectionGraph {
        try CurrentTaskCancellationChecker().checkCancellation()
        let operands = BooleanOperandContext(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID,
            solidities: try BooleanOperandSolidities.resolve(materials, targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID, model: model, tolerance: tolerance))
        let classification = try pipeline.classificationGraph(uvSplitGraph: uvSplitGraph,
            targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID, model: model,
            operands: operands, tolerance: tolerance)
        let selected = try pipeline.regionSelectionGraph(operation: operation,
            classificationGraph: classification, rule: operands.rule, tolerance: tolerance)
        try CurrentTaskCancellationChecker().checkCancellation()
        return selected
    }

    /// Every dimensional section component with the original face pair and deterministic component ID.
    public var sections: [BooleanSectionComponent] {
        uvSplitGraph.splits.flatMap { split in
            split.components.map { component in
                BooleanSectionComponent(facePair: split.facePair, componentID: component.id,
                                        geometry: component.geometry)
            }
        }
    }
}
