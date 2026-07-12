import CADCore
import CADIR
import CADGeometry

public enum BooleanPipelinePhase: String, Codable, Hashable, Sendable, CaseIterable {
    case operandValidation
    case facePairBroadPhase
    case curveSurfaceIntersection
    case uvFaceSplitting
    case pointInSolidClassification
    case resultRegionSelection
    case sewing
    case topologyValidation
    case lineageGeneration
}

/// Fixed-order orchestration boundary for exact Boolean evaluators.
/// The concrete evaluator may reject a phase when its declared capability is incomplete,
/// but it cannot silently bypass validation or return an unvalidated B-rep.
public struct BooleanPipeline: Sendable {
    private let evaluator: any BRepBooleanEvaluating

    public init(evaluator: any BRepBooleanEvaluating) {
        self.evaluator = evaluator
    }

    public func evaluate(
        operation: SweepBooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        keepTools: Bool,
        featureID: FeatureID,
        model: BRepModel,
        generatedNames: [PersistentName: TopologyReference],
        toolGeneratedNames: [PersistentName: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult {
        do {
            try operandValidation(
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                model: model,
                tolerance: tolerance
            )
            try facePairBroadPhase(
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                operation: operation,
                in: model,
                tolerance: tolerance
            )

            // Intersection, UV splitting, classification, region selection, and sewing
            // are delegated to the exact evaluator in this fixed sequence contract.
            let result = try evaluator.evaluate(
                operation: operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                keepTools: keepTools,
                featureID: featureID,
                model: model,
                generatedNames: generatedNames,
                toolGeneratedNames: toolGeneratedNames,
                tolerance: tolerance
            )
            try result.brep.validate(tolerance: tolerance)
            return result
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .topology,
                featureID: featureID,
                tolerance: tolerance
            )
        }
    }

    private func operandValidation(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard !targetBodyIDs.isEmpty,
              Set(targetBodyIDs).count == targetBodyIDs.count,
              !targetBodyIDs.contains(toolBodyID) else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean operands must be distinct and contain at least one target."
            )
        }
        for bodyID in targetBodyIDs + [toolBodyID] {
            guard model.bodies[bodyID] != nil else {
                throw KernelError(
                    phase: .validation,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean operand body is missing."
                )
            }
        }
        try model.validate(tolerance: tolerance)
    }

    private func facePairBroadPhase(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        operation: SweepBooleanOperation,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        guard operation != .newBody else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean pipeline requires a target operation."
            )
        }
        let toolBounds = try bounds(for: toolBodyID, in: model)
        guard let toolBounds else {
            throw KernelError(
                phase: .geometry,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Boolean tool has no finite face-pair bounds."
            )
        }
        var hasCandidate = false
        for targetBodyID in targetBodyIDs {
            if let targetBounds = try bounds(for: targetBodyID, in: model),
               targetBounds.intersects(toolBounds, tolerance: tolerance.distance) {
                hasCandidate = true
                break
            }
        }
        guard hasCandidate else {
            if operation == .union {
                return
            }
            throw KernelError(
                phase: .geometry,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Boolean face-pair broad phase found no candidate intersection."
            )
        }
    }

    private func bounds(for bodyID: BodyID, in model: BRepModel) throws -> BoundingBox3D? {
        guard let body = model.bodies[bodyID] else { return nil }
        let points = body.shellIDs.flatMap { shellID in
            model.shells[shellID]?.faceIDs.flatMap { faceID in
                model.faces[faceID]?.loops.flatMap { loopID in
                    model.loops[loopID]?.edges.flatMap { coedge in
                        guard let edge = model.edges[coedge.edgeID] else { return [Point3D]() }
                        return [model.vertices[edge.startVertexID]?.point, model.vertices[edge.endVertexID]?.point].compactMap { $0 }
                    } ?? []
                } ?? []
            } ?? []
        }
        guard points.isEmpty == false else { return nil }
        return try BoundingBox3D(points: points)
    }
}
