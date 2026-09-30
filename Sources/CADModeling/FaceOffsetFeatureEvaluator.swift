import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct FaceOffsetFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving
    private let identityBuilder: any CarriedTopologyIdentityBuilding

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
        identityBuilder = DefaultCarriedTopologyIdentityBuilder()
    }

    public func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try evaluateFaceOffset(feature: feature, context: context)
        }
    }

    private func evaluateFaceOffset(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .faceOffset(offset) = feature.operation else {
            throw kernelError(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Face offset evaluator requires a faceOffset feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try offset.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let distance = try resolvedDistance(offset.distance, featureID: feature.id, context: context)
        let adjacentAngle = try offset.adjacentAngle.map { try resolvedAngle($0, featureID: feature.id, context: context) } ?? 0
        let bodyID = try context.bodyID(generatedBy: offset.target.featureID)
        let bodyScope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
        let faceIDs = try offset.faces.map {
            try targetFaceID($0, bodyScope: bodyScope, featureID: feature.id, context: context)
        }
        let replacedSubshapeIDs = bodyScope.subshapeIDs(in: context.subshapes)
        var model = context.brep
        // Each face moves along its outward side onto the offset of its own surface.
        var replacements: [FaceID: FaceSurfaceReplacementRebuilder.Replacement] = [:]
        for faceID in faceIDs {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Face offset face is missing.")
            }
            replacements[faceID] = FaceSurfaceReplacementRebuilder.Replacement(
                surface: try FaceSurfaceOffsetter().offset(surface, orientation: face.orientation, by: distance, tolerance: context.tolerance),
                orientation: face.orientation
            )
        }
        if adjacentAngle != 0 {
            for (faceID, surface) in try tiltedNeighbours(
                of: Set(faceIDs), by: adjacentAngle, bodyScope: bodyScope, featureID: feature.id, model: model, tolerance: context.tolerance
            ) {
                guard let face = model.faces[faceID] else { throw TopologyError.missingReference("Face offset face is missing.") }
                replacements[faceID] = FaceSurfaceReplacementRebuilder.Replacement(surface: surface, orientation: face.orientation)
            }
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): every Grow mode re-solves the faces around the pushed
        // faces in place, so a push that runs into another wall is refused as a topology failure
        // under Moving and Fixed too. Production path: FaceOffsetFeatureEvaluator for every
        // faceOffset feature. Moving and Fixed are complete only when a pushed face meeting a wall
        // moves that wall or stops at it, verified by tests of a concave face pushed into a wall.
        try FaceSurfaceReplacementRebuilder().replace(
            replacements, bodyID: bodyID, featureID: feature.id, model: &model, tolerance: context.tolerance
        )
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: context.tolerance)
        let isSolid = model.bodies[bodyID]?.kind == .solid
        try model.validate(level: isSolid ? .volumetric : .exact, tolerance: context.tolerance)
        let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: model, context: context)
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: identity.lineage
        )
    }

    /// The planes the faces beside the pushed faces tilt onto: each planar neighbour of a pushed
    /// planar face turns about the straight edge they share by `angle`, a positive angle leaning
    /// it out from the pushed face.
    private func tiltedNeighbours(
        of pushed: Set<FaceID>,
        by angle: Double,
        bodyScope: BodyTopologyScope,
        featureID: FeatureID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [FaceID: Surface3D] {
        var facesOfEdge: [EdgeID: [FaceID]] = [:]
        for case let .face(faceID) in bodyScope.references {
            for loopID in model.faces[faceID]?.loops ?? [] {
                for coedge in model.loops[loopID]?.coedges ?? [] { facesOfEdge[coedge.edgeID, default: []].append(faceID) }
            }
        }
        let planes = DefaultPlanarSurfaceResolver()
        func outwardPlane(of faceID: FaceID) throws -> (origin: Point3D, surfaceNormal: Vector3D, outward: Vector3D)? {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Face offset face is missing.")
            }
            guard let plane = try planes.exactPlane(for: surface, tolerance: tolerance) else { return nil }
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            return (plane.origin, normal, face.orientation == .forward ? normal : normal * -1)
        }
        var tilted: [FaceID: Surface3D] = [:]
        for pushedID in pushed.sorted() {
            guard let pushedPlane = try outwardPlane(of: pushedID) else {
                throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "Push Face tilts the faces beside planar pushed faces only.")
            }
            for loopID in model.faces[pushedID]?.loops ?? [] {
                for coedge in model.loops[loopID]?.coedges ?? [] {
                    guard let neighbourID = facesOfEdge[coedge.edgeID]?.first(where: { $0 != pushedID }),
                          pushed.contains(neighbourID) == false else { continue }
                    guard let edge = model.edges[coedge.edgeID], case let .line(line) = model.geometry.curves[edge.curveID],
                          let neighbour = try outwardPlane(of: neighbourID) else {
                        throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                                          "Push Face tilts planar faces beside the pushed faces about straight edges only.")
                    }
                    let axis = try line.direction.normalized(tolerance: tolerance.distance)
                    // The tilt that turns the neighbour's outward side away from the pushed face.
                    var turned = rotated(neighbour.outward, about: axis, by: angle)
                    var signedAngle = angle
                    if (turned - neighbour.outward).dot(pushedPlane.outward) > 0 {
                        signedAngle = -angle
                        turned = rotated(neighbour.outward, about: axis, by: signedAngle)
                    }
                    let plane = Surface3D.plane(Plane3D(origin: line.origin, normal: rotated(neighbour.surfaceNormal, about: axis, by: signedAngle)))
                    if let earlier = tilted[neighbourID], earlier != plane {
                        throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                                          "Push Face cannot tilt a face about two different pushed edges.")
                    }
                    tilted[neighbourID] = plane
                }
            }
        }
        return tilted
    }

    /// `vector` turned `angle` about the unit `axis` (right-handed).
    private func rotated(_ vector: Vector3D, about axis: Vector3D, by angle: Double) -> Vector3D {
        vector * cos(angle) + axis.cross(vector) * sin(angle) + axis * (axis.dot(vector) * (1 - cos(angle)))
    }

    private func resolvedAngle(_ expression: CADExpression, featureID: FeatureID, context: EvaluationContext) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .angle else {
            throw UnitError.expectedQuantity(operation: "faceOffset.adjacentAngle", expected: .angle, actual: quantity.kind)
        }
        guard quantity.value.isFinite, abs(quantity.value) < Double.pi / 2 else {
            throw kernelError(.invalidInput, featureID: featureID, tolerance: context.tolerance, "Push Face adjacent angle must lie strictly between -90 and 90 degrees.")
        }
        return quantity.value
    }

    private func resolvedDistance(
        _ expression: CADExpression,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(operation: "faceOffset.distance", expected: .length, actual: quantity.kind)
        }
        guard quantity.value.isFinite, abs(quantity.value) > context.tolerance.distance else {
            throw kernelError(.invalidInput, featureID: featureID, tolerance: context.tolerance, "Face offset distance must be finite and larger than modeling tolerance.")
        }
        return quantity.value
    }

    private func targetFaceID(
        _ stableReference: StableSubshapeReference,
        bodyScope: BodyTopologyScope,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> FaceID {
        let reference = try subshapeResolver.topologyReference(
            for: stableReference,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .face(faceID) = reference else {
            throw kernelError(.missingReference, featureID: featureID, subshapeID: stableReference.subshapeID, tolerance: context.tolerance, "Face offset target face could not be resolved.")
        }
        guard bodyScope.references.contains(.face(faceID)) else {
            throw kernelError(
                .missingReference,
                featureID: featureID,
                subshapeID: stableReference.subshapeID,
                tolerance: context.tolerance,
                "Face offset target face does not belong to the target body."
            )
        }
        return faceID
    }

    private func kernelError(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        subshapeID: SubshapeID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            subshapeID: subshapeID,
            tolerance: tolerance,
            message: message
        )
    }
}
