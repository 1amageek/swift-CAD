import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Draft Face, isocline: each drafted face turns about where it crosses the neutral plane so it
/// makes the draft angle with the pull direction, and the faces around it are re-solved to meet
/// it (`FaceSurfaceReplacementRebuilder`). A planar face becomes the plane through its pivot line;
/// a cylinder along the pull direction becomes the cone through its pivot circle.
public struct FaceDraftFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
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
            try evaluateFaceDraft(feature: feature, context: context)
        }
    }

    private func evaluateFaceDraft(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .faceDraft(draft) = feature.operation else {
            throw kernelError(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Face draft evaluator requires a faceDraft feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try draft.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        let angle = try resolvedAngle(draft.angle, featureID: feature.id, context: context)
        let neutralOffset = try draft.neutralOffset.map { try resolvedLength($0, featureID: feature.id, context: context) } ?? 0
        let bodyID = try context.bodyID(generatedBy: draft.target.featureID)
        guard context.brep.bodies[bodyID]?.kind == .solid else {
            throw kernelError(.unsupportedCapability, featureID: feature.id, tolerance: tolerance, "Face draft requires a solid target body.")
        }
        let bodyScope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
        var faceIDs: [FaceID] = []
        for reference in draft.faces {
            let faceID = try targetFaceID(reference, bodyScope: bodyScope, featureID: feature.id, context: context)
            guard faceIDs.contains(faceID) == false else {
                throw kernelError(.invalidInput, featureID: feature.id, subshapeID: reference.subshapeID, tolerance: tolerance,
                                  "Face draft selections resolve to the same face.")
            }
            faceIDs.append(faceID)
        }
        let neutralFaceID = try targetFaceID(draft.neutralFace, bodyScope: bodyScope, featureID: feature.id, context: context)
        guard faceIDs.contains(neutralFaceID) == false else {
            throw kernelError(.invalidInput, featureID: feature.id, subshapeID: draft.neutralFace.subshapeID, tolerance: tolerance,
                              "Face draft neutral face must be distinct from its target faces.")
        }
        var model = context.brep
        // The neutral plane and the pull direction: the neutral face's plane, moved along its
        // outward side by the offset, and that outward side.
        guard let neutralFace = model.faces[neutralFaceID], let neutralSurface = model.geometry.surfaces[neutralFace.surfaceID],
              let neutralPlane = try DefaultPlanarSurfaceResolver().exactPlane(for: neutralSurface, tolerance: tolerance) else {
            throw kernelError(.unsupportedCapability, featureID: feature.id, subshapeID: draft.neutralFace.subshapeID, tolerance: tolerance,
                              "Face draft needs a planar neutral face.")
        }
        let planeNormal = try neutralPlane.normal.normalized(tolerance: tolerance.distance)
        let pull = neutralFace.orientation == .forward ? planeNormal : planeNormal * -1
        let neutralOrigin = neutralPlane.origin + pull * neutralOffset

        var replacements: [FaceID: FaceSurfaceReplacementRebuilder.Replacement] = [:]
        for faceID in faceIDs.sorted() {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Face draft face is missing.")
            }
            let drafted = try draftedSurface(
                of: face, surface: surface, pull: pull, neutralOrigin: neutralOrigin, angle: angle,
                featureID: feature.id, model: model, tolerance: tolerance
            )
            replacements[faceID] = drafted
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): every Grow mode re-solves the faces around the drafted
        // faces in place, so a draft that runs into another wall is refused as a topology failure
        // under Moving and Fixed too. Production path: FaceDraftFeatureEvaluator for every
        // faceDraft feature. Moving and Fixed are complete only when a drafted face meeting a wall
        // extends that wall or stops at it, verified by tests of a concave face drafted into a wall.
        try FaceSurfaceReplacementRebuilder().replace(replacements, bodyID: bodyID, featureID: feature.id, model: &model, tolerance: tolerance)
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: tolerance)
        try model.validate(level: .volumetric, tolerance: tolerance)
        let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: model, context: context)
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: bodyScope.subshapeIDs(in: context.subshapes),
            lineage: identity.lineage
        )
    }

    /// The surface a drafted face turns onto: it turns as one surface about its crossing with the
    /// neutral plane (the pivot), leaning out by `angle` from the pull direction as it runs against
    /// the pull — in where it lies beyond the plane along the pull.
    private func draftedSurface(
        of face: Face,
        surface: Surface3D,
        pull: Vector3D,
        neutralOrigin: Point3D,
        angle: Double,
        featureID: FeatureID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> FaceSurfaceReplacementRebuilder.Replacement {
        let points = try face.loops.flatMap { try model.orderedPoints(for: $0) }
        let tangent = tan(angle)
        let replacement: Surface3D
        if let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) {
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            let outward = face.orientation == .forward ? normal : normal * -1
            // The pivot line, where the face's plane crosses the neutral plane.
            let lineDirection = normal.cross(pull)
            guard lineDirection.length > tolerance.angle else {
                throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                                  "Face draft cannot turn a face parallel to the neutral plane.")
            }
            let axis = try lineDirection.normalized(tolerance: tolerance.distance)
            let across = try (outward - pull * outward.dot(pull)).normalized(tolerance: tolerance.distance)
            // The pivot: the point of the face's plane on the neutral plane nearest its centre.
            let center = points.reduce(Vector3D.zero) { $0 + ($1 - .origin) } / Double(points.count)
            let onPlane = Point3D.origin + center
            let pivot = try pivotPoint(near: onPlane, planeOrigin: plane.origin, planeNormal: normal,
                                       neutralOrigin: neutralOrigin, pull: pull, tolerance: tolerance)
            // The face turns as one plane about the pivot line: running against the pull it leans
            // out along `across` by the angle (in along the pull, beyond the neutral plane).
            let running = pull * -1 + across * tangent
            var drafted = try axis.cross(running).normalized(tolerance: tolerance.distance)
            if drafted.dot(outward) < 0 { drafted = drafted * -1 }
            replacement = .plane(Plane3D(origin: pivot, normal: drafted))
        } else if let (origin, axis, radius) = cylinder(surface), axis.cross(pull).length <= tolerance.angle * max(axis.length, 1) {
            // The pivot circle lies where the cylinder crosses the neutral plane; the cone through it
            // widens or narrows along the pull direction as the face leans out.
            let unitAxis = try axis.normalized(tolerance: tolerance.distance)
            let center = origin + unitAxis * (neutralOrigin - origin).dot(unitAxis)
            let sample = try surface.differentialGeometry(u: 0, v: 0, tolerance: tolerance)
            let radial = sample.position - origin - unitAxis * (sample.position - origin).dot(unitAxis)
            let normalAway = sample.normal.dot(radial) > 0
            let outwardAway = normalAway == (face.orientation == .forward)
            // The radius changes by `tangent` per unit of height away from the plane, growing when
            // the face's outward side points away from the axis.
            let growth = outwardAway ? tangent : -tangent
            guard abs(growth) > tolerance.angle else {
                throw kernelError(.invalidInput, featureID: featureID, tolerance: tolerance, "Face draft angle is too small to turn a cylinder.")
            }
            // One cone through the pivot circle: radius r - growth * h along `pull * h`, zero at
            // h = r / growth.
            let apex = center + pull * (radius / growth)
            let opening = pull * (growth > 0 ? -1 : 1)
            replacement = .analytic(.cone(apex: apex, axis: opening, halfAngle: abs(angle)))
        } else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              "Face draft turns planar faces, and cylinders along the pull direction.")
        }
        // The drafted face keeps its outward side: its orientation follows the new surface's normal.
        let center = points.reduce(Vector3D.zero) { $0 + ($1 - .origin) } / Double(points.count)
        let before = try SurfaceFootResolver().foot(of: .origin + center, on: surface, tolerance: tolerance).normal
        let outwardBefore = face.orientation == .forward ? before : before * -1
        let after = try SurfaceFootResolver().foot(of: .origin + center, on: replacement, tolerance: tolerance).normal
        return FaceSurfaceReplacementRebuilder.Replacement(
            surface: replacement,
            orientation: after.dot(outwardBefore) > 0 ? .forward : .reversed
        )
    }

    /// The point on both the face's plane and the neutral plane nearest `point`.
    private func pivotPoint(
        near point: Point3D, planeOrigin: Point3D, planeNormal: Vector3D,
        neutralOrigin: Point3D, pull: Vector3D, tolerance: ModelingTolerance
    ) throws -> Point3D {
        // Solve n1·X = n1·o1, n2·X = n2·o2 and (n1×n2)·X = (n1×n2)·point.
        let along = planeNormal.cross(pull)
        let rows = [(planeNormal, planeNormal.dot(planeOrigin - .origin)), (pull, pull.dot(neutralOrigin - .origin)), (along, along.dot(point - .origin))]
        let m = rows.map { [$0.0.x, $0.0.y, $0.0.z] }
        func det(_ m: [[Double]]) -> Double {
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        }
        let d = det(m)
        guard abs(d) > tolerance.angle * tolerance.angle else {
            throw KernelError(phase: .evaluation, code: .unsupportedCapability, tolerance: tolerance, message: "Face draft cannot turn a face parallel to the neutral plane.")
        }
        var result = [0.0, 0.0, 0.0]
        for column in 0..<3 {
            var replaced = m
            for row in 0..<3 { replaced[row][column] = rows[row].1 }
            result[column] = det(replaced) / d
        }
        return Point3D(x: result[0], y: result[1], z: result[2])
    }

    private func cylinder(_ surface: Surface3D) -> (origin: Point3D, axis: Vector3D, radius: Double)? {
        switch surface {
        case let .cylinder(cylinder): (cylinder.origin, cylinder.axis, cylinder.radius)
        case let .analytic(.cylinder(origin, axis, radius)): (origin, axis, radius)
        default: nil
        }
    }

    private func resolvedAngle(_ expression: CADExpression, featureID: FeatureID, context: EvaluationContext) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .angle else {
            throw kernelError(.invalidInput, featureID: featureID, tolerance: context.tolerance, "Face draft angle must resolve to an angle quantity.")
        }
        guard quantity.value.isFinite, abs(quantity.value) > context.tolerance.angle else {
            throw kernelError(.invalidInput, featureID: featureID, residual: quantity.value, tolerance: context.tolerance,
                              "Face draft angle must be finite and larger than angular tolerance.")
        }
        guard abs(quantity.value) < Double.pi / 2.0 - context.tolerance.angle else {
            throw kernelError(.unsupportedCapability, featureID: featureID, residual: quantity.value, tolerance: context.tolerance,
                              "Face draft angle magnitude must be smaller than 90 degrees.")
        }
        return quantity.value
    }

    private func resolvedLength(_ expression: CADExpression, featureID: FeatureID, context: EvaluationContext) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length, quantity.value.isFinite else {
            throw kernelError(.invalidInput, featureID: featureID, tolerance: context.tolerance, "Face draft neutral offset must resolve to a finite length.")
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
            throw kernelError(.missingReference, featureID: featureID, subshapeID: stableReference.subshapeID, tolerance: context.tolerance,
                              "Face draft selection did not resolve to a face.")
        }
        guard bodyScope.references.contains(.face(faceID)) else {
            throw kernelError(.missingReference, featureID: featureID, subshapeID: stableReference.subshapeID, tolerance: context.tolerance,
                              "Face draft target and neutral faces must belong to the target body.")
        }
        return faceID
    }

    private func kernelError(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        subshapeID: SubshapeID? = nil,
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            subshapeID: subshapeID,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
