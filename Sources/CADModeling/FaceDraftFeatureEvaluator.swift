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
    private let sewer: (any BRepSewing)?
    private let applicator: (any BooleanOperationApplying)?

    /// Without a sewer and a Boolean applicator a drafted face that runs into another wall is
    /// refused under every Grow mode; with them it grows as `FaceDraftGrowWedgeBuilder` says.
    public init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver(),
        sewer: (any BRepSewing)? = nil,
        applicator: (any BooleanOperationApplying)? = nil
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
        self.sewer = sewer
        self.applicator = applicator
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
        // outward side by the offset, and that outward side. A curved reference has no plane to
        // move: each face turns about the edge it shares with it, pulled along its outward side
        // there.
        guard let neutralFace = model.faces[neutralFaceID], let neutralSurface = model.geometry.surfaces[neutralFace.surfaceID] else {
            throw TopologyError.missingReference("Face draft neutral face is missing.")
        }
        let neutralPlane = try DefaultPlanarSurfaceResolver().exactPlane(for: neutralSurface, tolerance: tolerance)
        if neutralPlane == nil, neutralOffset != 0 {
            throw kernelError(.invalidInput, featureID: feature.id, subshapeID: draft.neutralFace.subshapeID, tolerance: tolerance,
                              "Face draft offsets only a planar reference face.")
        }
        var hinges: [FaceID: (pull: Vector3D, origin: Point3D)] = [:]
        for faceID in faceIDs {
            if let neutralPlane {
                let planeNormal = try neutralPlane.normal.normalized(tolerance: tolerance.distance)
                let pull = neutralFace.orientation == .forward ? planeNormal : planeNormal * -1
                hinges[faceID] = (pull, neutralPlane.origin + pull * neutralOffset)
            } else {
                hinges[faceID] = try sharedEdgeHinge(of: faceID, reference: neutralFace, referenceSurface: neutralSurface,
                                                     featureID: feature.id, model: model, tolerance: tolerance)
            }
        }

        var replacements: [FaceID: FaceSurfaceReplacementRebuilder.Replacement] = [:]
        for faceID in faceIDs.sorted() {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID], let hinge = hinges[faceID] else {
                throw TopologyError.missingReference("Face draft face is missing.")
            }
            let drafted = try draftedSurface(
                of: face, surface: surface, pull: hinge.pull, neutralOrigin: hinge.origin, angle: angle,
                featureID: feature.id, model: model, tolerance: tolerance
            )
            replacements[faceID] = drafted
        }
        do {
            try FaceSurfaceReplacementRebuilder().replace(replacements, bodyID: bodyID, featureID: feature.id, model: &model, tolerance: tolerance)
        } catch let error as KernelError where error.code == .topologyFailure {
            // The drafted faces ran into another wall, so the faces around them cannot simply be
            // re-solved: Grow decides how far the drafted face reaches.
            // FIXME(INCOMPLETE_IMPLEMENTATION): Grow reaches past another wall only for one planar
            // drafted face; several faces, or a cylinder, running into a wall are refused with the
            // re-solve's topology failure. Production path: FaceDraftFeatureEvaluator for every
            // faceDraft feature. Complete when several drafted faces grow together, meeting each
            // other's wedges, verified by a frustum whose walls run into another wall.
            guard replacements.count == 1, let (faceID, replacement) = replacements.first,
                  let pull = hinges[faceID]?.pull,
                  let grown = try grow(faceID: faceID, replacement: replacement, grow: draft.grow, pull: pull, bodyID: bodyID,
                                       featureID: feature.id, context: context) else {
                throw error
            }
            return grown
        }
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

    /// The body united with the material between `faceID`'s plane and its drafted plane, as far
    /// as `grow` lets the drafted face reach; nil when this evaluator cannot grow it.
    private func grow(
        faceID: FaceID,
        replacement: FaceSurfaceReplacementRebuilder.Replacement,
        grow: FaceEditGrow,
        pull: Vector3D,
        bodyID: BodyID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult? {
        let tolerance = context.tolerance
        guard let sewer, let applicator, case let .plane(drafted) = replacement.surface,
              let face = context.brep.faces[faceID], let surface = context.brep.geometry.surfaces[face.surfaceID],
              let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) else {
            return nil
        }
        let normal = try plane.normal.normalized(tolerance: tolerance.distance)
        guard let wedge = try FaceDraftGrowWedgeBuilder(tolerance: tolerance).wedge(
            for: .init(
                faceID: faceID,
                outward: face.orientation == .forward ? normal : normal * -1,
                normal: normal,
                draftedNormal: try drafted.normal.normalized(tolerance: tolerance.distance),
                pivot: drafted.origin,
                axis: normal.cross(pull),
                pull: pull
            ),
            grow: grow, bodyID: bodyID, model: context.brep, featureID: featureID
        ) else {
            return nil
        }
        let toolFeatureID = featureEvaluationStageID(featureID: featureID, domain: .draftGrowWedge, ordinal: 0)
        let request = try PolygonPrismRequestBuilder(tolerance: tolerance).request(
            featureID: toolFeatureID, polygon: wedge.polygon, axis: wedge.axis, length: wedge.length, stablePrefix: "draftGrow"
        )
        let tool = try sewer.sew(request, tolerance: tolerance)
        let toolBodyIDs = Set(tool.subshapes.values.compactMap { reference -> BodyID? in
            guard case let .body(id) = reference else { return nil }
            return id
        })
        guard toolBodyIDs.count == 1, let toolBodyID = toolBodyIDs.first else {
            throw kernelError(.topologyFailure, featureID: featureID, tolerance: tolerance, "A draft's grown wedge is not one body.")
        }
        var subshapes = context.subshapes.entries
        subshapes.merge(tool.subshapes) { current, _ in current }
        var lineage = context.lineage
        lineage.merge(tool.lineage) { current, _ in current }
        var result = try applicator.apply(
            operation: .union,
            targetBodyIDs: [bodyID],
            toolBodyID: toolBodyID,
            keepTools: false,
            featureID: featureID,
            model: try BRepModelCombiner().combined([context.brep, tool.brep]),
            subshapes: subshapes,
            toolSubshapes: tool.subshapes,
            inputLineage: lineage,
            tolerance: tolerance
        )
        // The wedge was never published, so its identities are neither removed nor parents.
        let toolSubshapeIDs = Set(tool.subshapes.keys)
        result.removedSubshapeIDs.subtract(toolSubshapeIDs)
        result.lineage = result.lineage.mapValues { entry in
            TopologyLineage(output: entry.output, parents: entry.parents.filter { !toolSubshapeIDs.contains($0) }, relation: entry.relation)
        }.withRelationsDerivedFromParents()
        return result
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

    /// Where a face turns about a curved reference: the straight edge it shares with it, pulled
    /// along the reference's outward side there, which must not turn along the edge.
    private func sharedEdgeHinge(
        of faceID: FaceID,
        reference: Face,
        referenceSurface: Surface3D,
        featureID: FeatureID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> (pull: Vector3D, origin: Point3D) {
        guard let face = model.faces[faceID] else { throw TopologyError.missingReference("Face draft face is missing.") }
        func edgeIDs(of face: Face) throws -> Set<EdgeID> {
            try Set(face.loops.flatMap { loopID -> [EdgeID] in
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Face draft loop is missing.") }
                return loop.coedges.map(\.edgeID)
            })
        }
        let shared = try edgeIDs(of: face).intersection(edgeIDs(of: reference))
        // FIXME(INCOMPLETE_IMPLEMENTATION): a face drafted about a curved reference turns only
        // about one straight shared edge along which the reference's normal stays put, so it stays
        // a plane; a face meeting the reference along a curve (which would turn into a ruled
        // surface) or not at all is refused here. Production path: FaceDraftFeatureEvaluator for a
        // faceDraft whose neutral face is not planar. Complete when a face hinged on a curved edge
        // of the reference drafts into its ruled surface, verified by an S-topped block's S side.
        let isStraight: (Edge) -> Bool = { edge in
            switch model.geometry.curves[edge.curveID] {
            case .line, .analytic(.line): true
            default: false
            }
        }
        guard shared.count == 1, let edgeID = shared.first, let edge = model.edges[edgeID], isStraight(edge),
              let start = model.vertices[edge.startVertexID]?.point, let end = model.vertices[edge.endVertexID]?.point else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              "A face drafted about a curved reference turns about one straight edge it shares with it.")
        }
        let middle = start + (end - start) * 0.5
        let normals = try [start, middle, end].map { point -> Vector3D in
            let normal = try SurfaceFootResolver().foot(of: point, on: referenceSurface, tolerance: tolerance).normal
            return reference.orientation == .forward ? normal : normal * -1
        }
        guard normals.allSatisfy({ $0.cross(normals[0]).length <= tolerance.angle }) else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              "A face drafted about a curved reference needs the reference to keep its normal along their edge.")
        }
        return (try normals[1].normalized(tolerance: tolerance.distance), middle)
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
