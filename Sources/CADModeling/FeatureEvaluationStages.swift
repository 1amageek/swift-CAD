import CADCore
import CADIR
import CADTopology

/// The internal stages of one feature's evaluation, chained on a staged context and published
/// as if the feature had acted on its inputs directly.
///
/// Each stage result lives under a stage identity (`featureEvaluationStageID`) that must never
/// escape: `publish` checks the final result keeps none of them, reports the inputs any stage
/// consumed as removed, and traces lineage through stage subshapes back to input subshapes.
package struct FeatureEvaluationStages {
    /// The context the next stage evaluates in: the input context with every stage applied.
    package private(set) var context: EvaluationContext
    private let input: EvaluationContext
    private var stageSubshapeIDs: Set<SubshapeID> = []
    private var stageLineage: [SubshapeID: TopologyLineage] = [:]
    private var consumedInputSubshapeIDs: Set<SubshapeID> = []

    package init(_ context: EvaluationContext) {
        self.context = context
        self.input = context
    }

    /// Whether any stage has been applied.
    package var isEmpty: Bool { stageSubshapeIDs.isEmpty && consumedInputSubshapeIDs.isEmpty }

    /// Applies a stage's result to the staged context.
    package mutating func apply(_ stage: EvaluationResult) {
        context.brep = stage.brep
        context.validatedBRep = nil
        for subshapeID in stage.removedSubshapeIDs {
            context.subshapes.entries.removeValue(forKey: subshapeID)
            if stageSubshapeIDs.contains(subshapeID) == false {
                consumedInputSubshapeIDs.insert(subshapeID)
            }
        }
        context.subshapes.entries.merge(stage.subshapes) { _, staged in staged }
        context.lineage.merge(stage.lineage) { _, staged in staged }
        stageSubshapeIDs.formUnion(stage.subshapes.keys)
        stageLineage.merge(stage.lineage) { _, staged in staged }
    }

    /// The one body a stage published.
    package func publishedBody(of stage: EvaluationResult, featureID: FeatureID, what: String) throws -> BodyID {
        let bodyIDs = Set(stage.subshapes.values.compactMap { reference -> BodyID? in
            guard case let .body(bodyID) = reference else { return nil }
            return bodyID
        })
        guard bodyIDs.count == 1, let bodyID = bodyIDs.first else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                featureID: featureID,
                tolerance: context.tolerance,
                message: "\(what) did not publish exactly one body."
            )
        }
        return bodyID
    }

    /// The final result, computed in the staged context, published against the input context.
    package func publish(_ final: EvaluationResult, featureID: FeatureID) throws -> EvaluationResult {
        guard isEmpty == false else { return final }
        guard final.subshapes.keys.allSatisfy({ stageSubshapeIDs.contains($0) == false }) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                featureID: featureID,
                tolerance: context.tolerance,
                message: "A staged evaluation left a temporary identity in its result."
            )
        }
        var result = final
        result.removedSubshapeIDs = final.removedSubshapeIDs
            .subtracting(stageSubshapeIDs)
            .union(consumedInputSubshapeIDs)
        var traced: [SubshapeID: Set<SubshapeID>] = [:]
        func inputs(of subshapeID: SubshapeID, visiting: Set<SubshapeID>) throws -> Set<SubshapeID> {
            guard stageSubshapeIDs.contains(subshapeID) else { return [subshapeID] }
            if let known = traced[subshapeID] { return known }
            guard visiting.contains(subshapeID) == false else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    featureID: featureID,
                    tolerance: context.tolerance,
                    message: "A staged evaluation's lineage runs in a cycle."
                )
            }
            var parents = Set<SubshapeID>()
            for parent in stageLineage[subshapeID]?.parents ?? [] {
                parents.formUnion(try inputs(of: parent, visiting: visiting.union([subshapeID])))
            }
            traced[subshapeID] = parents
            return parents
        }
        var lineage: [SubshapeID: TopologyLineage] = [:]
        for (subshapeID, entry) in final.lineage {
            var parents = Set<SubshapeID>()
            for parent in entry.parents {
                parents.formUnion(try inputs(of: parent, visiting: []))
            }
            lineage[subshapeID] = TopologyLineage(output: entry.output, parents: parents.sorted(), relation: entry.relation)
        }
        result.lineage = lineage.withRelationsDerivedFromParents()
        return result
    }

    /// Puts input bodies a stage consumed back, unchanged, beside a published result: their
    /// topology from the input model, and their subshapes no longer reported as removed.
    package func restoringInputBodies(_ bodyIDs: [BodyID], into result: EvaluationResult) throws -> EvaluationResult {
        var restored = result
        restored.validatedBRep = nil
        let submodel = try BRepBodySubmodelExtractor().extract(bodyIDs: Set(bodyIDs), from: input.brep)
        try BRepModelCombiner().merge(submodel, into: &restored.brep)
        let bodySubshapes = input.subshapes.entries.filter { _, reference in
            bodyIDs.contains { input.brep.contains(reference, inBody: $0) }
        }
        restored.removedSubshapeIDs.subtract(bodySubshapes.keys)
        return restored
    }
}

extension BRepModel {
    /// Whether the topology `reference` names belongs to body `bodyID`.
    package func contains(_ reference: TopologyReference, inBody bodyID: BodyID) -> Bool {
        guard let body = bodies[bodyID] else {
            return false
        }
        let faceIDs = body.shellIDs.flatMap { shells[$0]?.faceIDs ?? [] }
        func edges(of faceID: FaceID) -> [EdgeID] {
            faces[faceID]?.loops.flatMap { loops[$0]?.edges.map(\.edgeID) ?? [] } ?? []
        }
        switch reference {
        case .body(let referenceBodyID):
            return referenceBodyID == bodyID
        case .face(let faceID):
            return faceIDs.contains(faceID)
        case .edge(let edgeID):
            return faceIDs.contains { edges(of: $0).contains(edgeID) }
        case .vertex(let vertexID):
            return faceIDs.contains { faceID in
                edges(of: faceID).contains { edgeID in
                    guard let edge = self.edges[edgeID] else { return false }
                    return edge.startVertexID == vertexID || edge.endVertexID == vertexID
                }
            }
        }
    }
}
