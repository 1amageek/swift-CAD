import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Match Face: the matched faces take the reference face's surface, placed in the target's frame,
/// and the faces around them are re-solved to meet them (`FaceSurfaceReplacementRebuilder`).
public struct FaceMatchFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let subshapeResolver: any StableSubshapeResolving
    private let identityBuilder: any CarriedTopologyIdentityBuilding

    public init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.subshapeResolver = subshapeResolver
        identityBuilder = DefaultCarriedTopologyIdentityBuilder()
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try evaluateFaceMatch(feature: feature, context: context)
        }
    }

    private func evaluateFaceMatch(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .faceMatch(match) = feature.operation else {
            throw failure(.invalidInput, feature.id, context.tolerance, "Match Face evaluator requires a faceMatch feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try match.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        let bodyID = try context.bodyID(generatedBy: match.target.featureID)
        let bodyScope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
        let sourceBodyID = try context.bodyID(generatedBy: match.source.featureID)
        let sourceScope = try BodyTopologyScope(bodyID: sourceBodyID, model: context.brep)
        let faceIDs = try match.faces.map { try faceID($0, in: bodyScope, featureID: feature.id, context: context) }
        guard Set(faceIDs).count == faceIDs.count else {
            throw failure(.invalidInput, feature.id, tolerance, "Match Face selections resolve to the same face.")
        }
        let referenceID = try faceID(match.referenceFace, in: sourceScope, featureID: feature.id, context: context)
        guard faceIDs.contains(referenceID) == false else {
            throw failure(.invalidInput, feature.id, tolerance, "Match Face cannot match a face to itself.")
        }
        var model = context.brep
        guard let reference = model.faces[referenceID], var surface = model.geometry.surfaces[reference.surfaceID] else {
            throw TopologyError.missingReference("Match Face reference face is missing.")
        }
        if let placement = match.sourcePlacement {
            surface = try placement.applying(to: surface, tolerance: tolerance)
        }
        let feet = SurfaceFootResolver()
        var replacements: [FaceID: FaceSurfaceReplacementRebuilder.Replacement] = [:]
        for faceID in faceIDs {
            guard let face = model.faces[faceID], let previous = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Match Face face is missing.")
            }
            let points = try face.loops.flatMap { try model.orderedPoints(for: $0) }
            guard points.isEmpty == false else {
                throw failure(.unsupportedCapability, feature.id, tolerance, "A matched face has no vertices to place it by.")
            }
            let center = Point3D.origin + points.reduce(Vector3D.zero) { $0 + ($1 - .origin) } / Double(points.count)
            let normal = try feet.foot(of: center, on: surface, tolerance: tolerance).normal
            let orientation: Orientation
            if match.front {
                // The reference face's front: its outward side, which a mirroring placement turns
                // to the surface's other side.
                let flips = match.sourcePlacement?.reversesOrientation ?? false
                orientation = (reference.orientation == .forward) != flips ? .forward : .reversed
            } else {
                let before = try feet.foot(of: center, on: previous, tolerance: tolerance).normal
                let outward = face.orientation == .forward ? before : before * -1
                orientation = normal.dot(outward) > 0 ? .forward : .reversed
            }
            replacements[faceID] = FaceSurfaceReplacementRebuilder.Replacement(surface: surface, orientation: orientation)
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): every Grow mode re-solves the faces around the matched
        // faces in place, so a match that runs into another wall is refused as a topology failure
        // under Moving and Fixed too. Production path: FaceMatchFeatureEvaluator for every
        // faceMatch feature. Moving and Fixed are complete only when a matched face meeting a wall
        // moves that wall or stops at it, verified by tests of a concave face matched past a wall.
        try FaceSurfaceReplacementRebuilder().replace(replacements, bodyID: bodyID, featureID: feature.id, model: &model, tolerance: tolerance)
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: tolerance)
        let isSolid = model.bodies[bodyID]?.kind == .solid
        try model.validate(level: isSolid ? .volumetric : .exact, tolerance: tolerance)
        let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: model, context: context)
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: bodyScope.subshapeIDs(in: context.subshapes),
            lineage: identity.lineage
        )
    }

    private func faceID(
        _ stableReference: StableSubshapeReference,
        in scope: BodyTopologyScope,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> FaceID {
        let reference = try subshapeResolver.topologyReference(
            for: stableReference, model: context.brep, subshapes: context.subshapes,
            lineage: context.lineage, tolerance: context.tolerance
        )
        guard case let .face(faceID) = reference, scope.references.contains(.face(faceID)) else {
            throw KernelError(
                phase: .evaluation, code: .missingReference, featureID: featureID, subshapeID: stableReference.subshapeID,
                tolerance: context.tolerance, message: "A Match Face selection did not resolve to a face of its body."
            )
        }
        return faceID
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
