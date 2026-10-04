import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct FaceOffsetFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving
    private let identityBuilder: any CarriedTopologyIdentityBuilding
    /// Extrude, for a pushed face that grows into a wall or past what its neighbours reach: the
    /// face extruded and joined to (or cut from) its body.
    private let faceExtruder: (any FeatureEvaluating)?

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver(),
        faceExtruder: (any FeatureEvaluating)? = nil
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
        self.faceExtruder = faceExtruder
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
        // Grow (Moving or Fixed): one planar face pushed out past a parallel wall of its body
        // facing the same way fills up to that wall (the face extruded and joined), then Moving
        // pushes the wall it became part of on by the rest of the distance.
        // FIXME(INCOMPLETE_IMPLEMENTATION): Grow reaches only a parallel wall of one planar face
        // pushed out; several faces, curved faces, oblique walls or an adjacent angle take the
        // in-place re-solve below, which fails explicitly where the faces around cannot follow.
        // Production path: Push Face (FaceOffsetFeatureEvaluator) with Grow Moving or Fixed.
        // Complete only when those faces grow into the walls they run into, verified by a face
        // pushed into an oblique wall and two faces pushed together.
        if offset.grow != .none, adjacentAngle == 0, faceIDs.count == 1, distance > 0,
           let pushed = try outwardPlane(of: faceIDs[0], model: context.brep, tolerance: context.tolerance),
           let gap = try wallGap(from: faceIDs[0], plane: pushed, distance: distance, bodyScope: bodyScope, model: context.brep,
                                 tolerance: context.tolerance) {
            return try grownToWall(offset, feature: feature, plane: pushed, gap: gap, distance: distance,
                                   removing: replacedSubshapeIDs, context: context)
        }
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
        // The faces around re-solved in place; under None a single planar face whose neighbours
        // cannot follow it keeps going by itself: extruded and joined to its body (outward) or cut
        // from it (inward).
        do {
            try FaceSurfaceReplacementRebuilder().replace(
                replacements, bodyID: bodyID, featureID: feature.id, model: &model, tolerance: context.tolerance
            )
            try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: context.tolerance)
            let isSolid = model.bodies[bodyID]?.kind == .solid
            try model.validate(level: isSolid ? .volumetric : .exact, tolerance: context.tolerance)
        } catch {
            guard offset.grow == .none, adjacentAngle == 0, faceIDs.count == 1,
                  let pushed = try outwardPlane(of: faceIDs[0], model: context.brep, tolerance: context.tolerance) else { throw error }
            return try extruded(offset, feature: feature, plane: pushed, distance: distance, context: context)
        }
        let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: model, context: context)
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: identity.lineage
        )
    }

    /// A planar face's plane: a point of it, its surface normal and its outward normal; nil for
    /// any other face.
    private func outwardPlane(of faceID: FaceID, model: BRepModel, tolerance: ModelingTolerance)
        throws -> (origin: Point3D, surfaceNormal: Vector3D, outward: Vector3D)? {
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("Face offset face is missing.")
        }
        guard let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) else { return nil }
        let normal = try plane.normal.normalized(tolerance: tolerance.distance)
        return (plane.origin, normal, face.orientation == .forward ? normal : normal * -1)
    }

    /// How far out the nearest wall a pushed planar face runs into lies: a planar face of its body
    /// facing the same way whose plane the push crosses short of its distance; nil when none.
    private func wallGap(from faceID: FaceID, plane: (origin: Point3D, surfaceNormal: Vector3D, outward: Vector3D), distance: Double,
                         bodyScope: BodyTopologyScope, model: BRepModel, tolerance: ModelingTolerance) throws -> Double? {
        var nearest: Double?
        for case let .face(otherID) in bodyScope.references where otherID != faceID {
            guard let other = try outwardPlane(of: otherID, model: model, tolerance: tolerance),
                  other.outward.dot(plane.outward) >= 1 - tolerance.angle else { continue }
            let gap = (other.origin - plane.origin).dot(plane.outward)
            guard gap > tolerance.distance, gap < distance - tolerance.distance else { continue }
            nearest = min(nearest ?? gap, gap)
        }
        return nearest
    }

    /// The pushed face extruded by `extent` (outward, joined; inward, cut) with the Extrude its
    /// evaluator was given.
    private func extrusion(_ offset: FaceOffsetFeature, feature: FeatureNode, extent: Double, inward: Vector3D?,
                           context: EvaluationContext) throws -> EvaluationResult {
        guard let faceExtruder else {
            throw kernelError(.unsupportedCapability, featureID: feature.id, tolerance: context.tolerance,
                              "Push Face's Grow needs an Extrude to carry the face past its neighbours.")
        }
        let node = FeatureNode(id: feature.id, name: feature.name, operation: .extrude(ExtrudeFeature(
            section: .face(FaceSectionReference(featureID: offset.target.featureID, face: offset.faces[0], bodyRole: .body)),
            distance: .constant(.length(extent, unit: .meter)), direction: inward.map { .vector($0) } ?? .normal,
            operation: inward == nil ? .union : .difference,
            targets: [BooleanTargetReference(featureID: offset.target.featureID)], resultKind: .solid
        )), outputs: feature.outputs)
        return try faceExtruder.evaluate(feature: node, context: context)
    }

    /// None past the neighbours: the face extruded its whole distance, joined outward, cut inward.
    private func extruded(_ offset: FaceOffsetFeature, feature: FeatureNode, plane: (origin: Point3D, surfaceNormal: Vector3D, outward: Vector3D),
                          distance: Double, context: EvaluationContext) throws -> EvaluationResult {
        try extrusion(offset, feature: feature, extent: abs(distance), inward: distance < 0 ? plane.outward * -1 : nil, context: context)
    }

    /// Moving or Fixed into a wall: the face filled up to the wall (extruded by the gap and
    /// joined); under Moving the face it then shares with the wall pushed on by the rest.
    private func grownToWall(_ offset: FaceOffsetFeature, feature: FeatureNode, plane: (origin: Point3D, surfaceNormal: Vector3D, outward: Vector3D),
                             gap: Double, distance: Double, removing replacedSubshapeIDs: Set<SubshapeID>,
                             context: EvaluationContext) throws -> EvaluationResult {
        let filled = try extrusion(offset, feature: feature, extent: gap, inward: nil, context: context)
        guard offset.grow == .moving else { return filled }
        var model = filled.brep
        guard let bodyID = filled.subshapes.compactMap({ key, value -> BodyID? in
            guard key.featureID == feature.id, case let .body(id) = value else { return nil }
            return id
        }).first else {
            throw TopologyError.missingReference("Push Face's filled body is missing.")
        }
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        let walls = try scope.references.compactMap { reference -> FaceID? in
            guard case let .face(faceID) = reference, let wall = try outwardPlane(of: faceID, model: model, tolerance: context.tolerance),
                  wall.outward.dot(plane.outward) >= 1 - context.tolerance.angle,
                  abs((wall.origin - plane.origin).dot(plane.outward) - gap) <= context.tolerance.distance else { return nil }
            return faceID
        }
        guard walls.isEmpty == false else {
            throw kernelError(.topologyFailure, featureID: feature.id, tolerance: context.tolerance, "Push Face's filled face did not join its wall.")
        }
        var replacements: [FaceID: FaceSurfaceReplacementRebuilder.Replacement] = [:]
        for faceID in walls {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Push Face's wall is missing.")
            }
            replacements[faceID] = FaceSurfaceReplacementRebuilder.Replacement(
                surface: try FaceSurfaceOffsetter().offset(surface, orientation: face.orientation, by: distance - gap, tolerance: context.tolerance),
                orientation: face.orientation
            )
        }
        try FaceSurfaceReplacementRebuilder().replace(replacements, bodyID: bodyID, featureID: feature.id, model: &model, tolerance: context.tolerance)
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: context.tolerance)
        try model.validate(level: .volumetric, tolerance: context.tolerance)
        let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: model, context: context)
        return EvaluationResult(brep: model, subshapes: identity.subshapes,
                                removedSubshapeIDs: replacedSubshapeIDs.union(filled.removedSubshapeIDs),
                                lineage: identity.lineage)
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
