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
        var hinges: [FaceID: Hinge] = [:]
        switch draft.method {
        case .isocline, .normal:
            // On a planar reference its normal is the one pull direction; on a curved one each face
            // takes the reference's normal along the edge they share.
            for faceID in faceIDs {
                if let neutralPlane {
                    let planeNormal = try neutralPlane.normal.normalized(tolerance: tolerance.distance)
                    let pull = neutralFace.orientation == .forward ? planeNormal : planeNormal * -1
                    hinges[faceID] = .pivot(pull: pull, origin: neutralPlane.origin + pull * neutralOffset)
                } else {
                    hinges[faceID] = try sharedEdgeHinge(of: faceID, reference: neutralFace, referenceSurface: neutralSurface,
                                                         featureID: feature.id, model: model, tolerance: tolerance)
                }
            }
        case let .curve(pivots):
            guard let neutralPlane else {
                throw kernelError(.unsupportedCapability, featureID: feature.id, subshapeID: draft.neutralFace.subshapeID, tolerance: tolerance,
                                  "A curve draft takes its pull direction from a planar reference face.")
            }
            let planeNormal = try neutralPlane.normal.normalized(tolerance: tolerance.distance)
            let pull = neutralFace.orientation == .forward ? planeNormal : planeNormal * -1
            let pivotEdges = try pivots.map { try targetEdgeID($0, bodyScope: bodyScope, featureID: feature.id, context: context) }
            for faceID in faceIDs {
                hinges[faceID] = try pivotEdgeHinge(of: faceID, among: pivotEdges, pull: pull, featureID: feature.id,
                                                    model: model, tolerance: tolerance)
            }
        case let .surface(reference):
            guard let neutralPlane else {
                throw kernelError(.unsupportedCapability, featureID: feature.id, subshapeID: draft.neutralFace.subshapeID, tolerance: tolerance,
                                  "A surface draft turns faces about a planar reference face's plane.")
            }
            let referenceFaceID = try targetFaceID(reference, bodyScope: bodyScope, featureID: feature.id, context: context)
            guard let referenceFace = model.faces[referenceFaceID], let referenceSurface = model.geometry.surfaces[referenceFace.surfaceID],
                  let referencePlane = try DefaultPlanarSurfaceResolver().exactPlane(for: referenceSurface, tolerance: tolerance) else {
                throw kernelError(.unsupportedCapability, featureID: feature.id, subshapeID: reference.subshapeID, tolerance: tolerance,
                                  "A surface draft takes its pull direction from a planar face.")
            }
            let referenceNormal = try referencePlane.normal.normalized(tolerance: tolerance.distance)
            let pull = referenceFace.orientation == .forward ? referenceNormal : referenceNormal * -1
            let planeNormal = try neutralPlane.normal.normalized(tolerance: tolerance.distance)
            let neutralNormal = neutralFace.orientation == .forward ? planeNormal : planeNormal * -1
            for faceID in faceIDs {
                hinges[faceID] = .tilted(pull: pull, origin: neutralPlane.origin + neutralNormal * neutralOffset, neutralNormal: neutralNormal)
            }
        }

        var replacements: [FaceID: FaceSurfaceReplacementRebuilder.Replacement] = [:]
        for faceID in faceIDs.sorted() {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID], let hinge = hinges[faceID] else {
                throw TopologyError.missingReference("Face draft face is missing.")
            }
            switch hinge {
            case let .pivot(pull, origin):
                replacements[faceID] = try draftedSurface(
                    of: face, surface: surface, pull: pull, neutralOrigin: origin, angle: angle,
                    featureID: feature.id, model: model, tolerance: tolerance
                )
            case let .tilted(pull, origin, neutralNormal):
                replacements[faceID] = try tiltedSurface(
                    of: face, surface: surface, pull: pull, neutralOrigin: origin, neutralNormal: neutralNormal, angle: angle,
                    featureID: feature.id, model: model, tolerance: tolerance
                )
            case let .curve(edgeID):
                replacements[faceID] = try curvedHingeSurface(
                    of: face, surface: surface, edgeID: edgeID, reference: neutralFace, referenceSurface: neutralSurface,
                    angle: angle, featureID: feature.id, model: model, tolerance: tolerance
                )
            }
        }
        do {
            try FaceSurfaceReplacementRebuilder().replace(replacements, bodyID: bodyID, featureID: feature.id, model: &model, tolerance: tolerance)
        } catch let error as KernelError where error.code == .topologyFailure {
            // The drafted faces ran into another wall, so the faces around them cannot simply be
            // re-solved: Grow decides how far the drafted face reaches.
            // FIXME(INCOMPLETE_IMPLEMENTATION): Planar Grow composes every selected
            // original wedge, but curved-wall Grow and complete curved-body envelopes
            // still require their original material producers. Full FaceDraft completion
            // requires those families, rather than success of this planar composition.
            guard let grown = try grow(replacements: replacements, hinges: hinges,
                grow: draft.grow, bodyID: bodyID, featureID: feature.id, context: context) else {
                throw error
            }
            return grown
        }
        do {
            try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: tolerance)
        } catch let error as KernelError {
            throw KernelError(phase: error.phase, code: error.code, featureID: error.featureID,
                subshapeID: error.subshapeID, residual: error.residual, tolerance: error.tolerance,
                message: "Draft final missing-pcurve population: \(error.message)")
        }
        do {
            try model.validate(level: .volumetric, tolerance: tolerance)
        } catch let error as KernelError {
            var replacementContext = ""
            for (faceID, replacement) in replacements.sorted(by: { $0.key < $1.key }) {
                if case let .bSpline(surface) = replacement.surface {
                    var uSpans = 0, vSpans = 0
                    for index in surface.uKnots.indices where index >= surface.uDegree &&
                        index < surface.uControlPointCount && index + 1 < surface.uKnots.count {
                        if surface.uKnots[index] < surface.uKnots[index + 1] { uSpans += 1 }
                    }
                    for index in surface.vKnots.indices where index >= surface.vDegree &&
                        index < surface.vControlPointCount && index + 1 < surface.vKnots.count {
                        if surface.vKnots[index] < surface.vKnots[index + 1] { vSpans += 1 }
                    }
                    replacementContext += " face=\(faceID) case=bSpline degree=[\(surface.uDegree),\(surface.vDegree)] controls=[\(surface.uControlPointCount),\(surface.vControlPointCount)] nativePositiveSpans=[\(uSpans),\(vSpans)]"
                } else {
                    replacementContext += " face=\(faceID) case=nonBSpline"
                }
            }
            throw KernelError(phase: error.phase, code: error.code, featureID: error.featureID,
                subshapeID: error.subshapeID, residual: error.residual, tolerance: error.tolerance,
                message: "Draft final volumetric validation\(replacementContext): \(error.message)")
        }
        let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: model, context: context)
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: try bodyScope.subshapeIDs(in: context.subshapes),
            lineage: identity.lineage
        )
    }

    /// Prepares all selected original planar wedges before one atomic Grow publication.
    private func grow(
        replacements: [FaceID: FaceSurfaceReplacementRebuilder.Replacement],
        hinges: [FaceID: Hinge], grow: FaceEditGrow, bodyID: BodyID,
        featureID: FeatureID, context: EvaluationContext
    ) throws -> EvaluationResult? {
        let tolerance = context.tolerance
        guard let sewer, let applicator else { return nil }
        var additions: [FaceDraftGrowWedgeBuilder.Wedge] = []
        var removals: [FaceDraftGrowWedgeBuilder.Wedge] = []
        var additiveFaces: Set<FaceID> = []
        for (faceID, replacement) in replacements.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            guard case let .plane(drafted) = replacement.surface,
                  case let .pivot(pull, _)? = hinges[faceID],
                  let face = context.brep.faces[faceID],
                  let surface = context.brep.geometry.surfaces[face.surfaceID],
                  let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface,
                    tolerance: tolerance) else { return nil }
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            guard let selected = try FaceDraftGrowWedgeBuilder(tolerance: tolerance).wedges(
                for: .init(faceID: faceID,
                    outward: face.orientation == .forward ? normal : normal * -1,
                    normal: normal,
                    draftedNormal: try drafted.normal.normalized(tolerance: tolerance.distance),
                    pivot: drafted.origin, axis: normal.cross(pull), pull: pull),
                grow: grow, bodyID: bodyID, model: context.brep, featureID: featureID),
                selected.isEmpty == false else { return nil }
            for wedge in selected {
                if wedge.removes { removals.append(wedge) }
                else { additions.append(wedge); additiveFaces.insert(faceID) }
            }
        }
        if grow == .moving, replacements.count > 1, !additiveFaces.isEmpty {
            var edgeOwners: [EdgeID: FaceID] = [:]
            for faceID in replacements.keys.sorted() {
                guard let face = context.brep.faces[faceID] else {
                    throw TopologyError.missingReference("Original drafted face is missing during corner admission.")
                }
                for loopID in face.loops {
                    guard let loop = context.brep.loops[loopID] else {
                        throw TopologyError.missingReference("Original drafted loop is missing during corner admission.")
                    }
                    for coedge in loop.coedges {
                        try Task.checkCancellation()
                        if let previous = edgeOwners[coedge.edgeID], previous != faceID,
                           additiveFaces.contains(previous) || additiveFaces.contains(faceID) {
                            // FIXME(INCOMPLETE_IMPLEMENTATION): Adjacent Moving draft
                            // walls with outward growth require their coupled original
                            // corner envelope. Independent finite prism union leaves a
                            // missing or excess corner and cannot authorize publication.
                            return nil
                        }
                        edgeOwners[coedge.edgeID] = faceID
                    }
                }
            }
        }
        let wedges = additions + removals
        guard wedges.isEmpty == false else { return nil }
        // Each wedge united or taken off in turn, the last under the feature.
        var stages = FeatureEvaluationStages(context)
        var target = bodyID
        for (index, wedge) in wedges.enumerated() {
            let staged = stages.context
            let last = index == wedges.count - 1
            let stageID = last ? featureID : featureEvaluationStageID(featureID: featureID, domain: .draftGrowWedge, ordinal: UInt64(index + 1))
            let toolFeatureID = featureEvaluationStageID(featureID: featureID, domain: .draftGrowWedge, ordinal: UInt64(index) << 32)
            let request = try PolygonPrismRequestBuilder(tolerance: tolerance).request(
                featureID: toolFeatureID, polygon: wedge.polygon, axis: wedge.axis, length: wedge.length, stablePrefix: "draftGrow\(index)"
            )
            let tool = try sewer.sew(request, tolerance: tolerance)
            let toolBodyIDs = Set(tool.subshapes.values.compactMap { reference -> BodyID? in
                guard case let .body(id) = reference else { return nil }
                return id
            })
            guard toolBodyIDs.count == 1, let toolBodyID = toolBodyIDs.first else {
                throw kernelError(.topologyFailure, featureID: featureID, tolerance: tolerance, "A draft's grown wedge is not one body.")
            }
            var subshapes = staged.subshapes.entries
            subshapes.merge(tool.subshapes) { current, _ in current }
            var lineage = staged.lineage
            lineage.merge(tool.lineage) { current, _ in current }
            var step = try applicator.apply(
                operation: wedge.removes ? .difference : .union,
                targetBodyIDs: [target],
                toolBodyID: toolBodyID,
                keepTools: false,
                featureID: stageID,
                model: try BRepModelCombiner().combined([staged.brep, tool.brep]),
                subshapes: subshapes,
                toolSubshapes: tool.subshapes,
                inputLineage: lineage,
                tolerance: tolerance
            )
            // The wedge was never published, so its identities are neither removed nor parents.
            let toolSubshapeIDs = Set(tool.subshapes.keys)
            step.removedSubshapeIDs.subtract(toolSubshapeIDs)
            step.lineage = step.lineage.mapValues { entry in
                TopologyLineage(output: entry.output, parents: entry.parents.filter { !toolSubshapeIDs.contains($0) }, relation: entry.relation)
            }.withRelationsDerivedFromParents()
            if last { return wedges.count == 1 ? step : try stages.publish(step, featureID: featureID) }
            stages.apply(step)
            target = try stages.publishedBody(of: step, featureID: featureID, what: "Growing a drafted face")
        }
        return nil
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
        return try keepingOutwardSide(of: face, surface: surface, on: replacement, model: model, tolerance: tolerance)
    }

    /// `replacement` as the face's new surface, the face keeping its outward side: its orientation
    /// follows the new surface's normal near the face's centre.
    private func keepingOutwardSide(
        of face: Face, surface: Surface3D, on replacement: Surface3D, model: BRepModel, tolerance: ModelingTolerance
    ) throws -> FaceSurfaceReplacementRebuilder.Replacement {
        let points = try face.loops.flatMap { try model.orderedPoints(for: $0) }
        let center = points.reduce(Vector3D.zero) { $0 + ($1 - .origin) } / Double(points.count)
        let before = try SurfaceFootResolver().foot(of: .origin + center, on: surface, tolerance: tolerance).normal
        let outwardBefore = face.orientation == .forward ? before : before * -1
        let after = try SurfaceFootResolver().foot(of: .origin + center, on: replacement, tolerance: tolerance).normal
        return FaceSurfaceReplacementRebuilder.Replacement(
            surface: replacement,
            orientation: after.dot(outwardBefore) > 0 ? .forward : .reversed
        )
    }

    /// Where a drafted face turns: about its crossing with the neutral plane (a pivot line through
    /// `origin`, pulled along `pull`), or about the curved edge it shares with a curved reference.
    private enum Hinge {
        case pivot(pull: Vector3D, origin: Point3D)
        /// About the face's crossing with the neutral plane (through `origin`, square to
        /// `neutralNormal`), the angle taken against another pull direction.
        case tilted(pull: Vector3D, origin: Point3D, neutralNormal: Vector3D)
        case curve(EdgeID)
    }

    /// A face drafted about the chosen straight edge lying on it, square to the pull direction:
    /// the isocline turn about the plane through that edge square to the pull.
    private func pivotEdgeHinge(of faceID: FaceID, among pivots: [EdgeID], pull: Vector3D, featureID: FeatureID,
                                model: BRepModel, tolerance: ModelingTolerance) throws -> Hinge {
        guard let face = model.faces[faceID] else { throw TopologyError.missingReference("Face draft face is missing.") }
        let faceEdges = Set(try face.loops.flatMap { loopID -> [EdgeID] in
            guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Face draft loop is missing.") }
            return loop.coedges.map(\.edgeID)
        })
        guard let edgeID = pivots.first(where: faceEdges.contains), let edge = model.edges[edgeID],
              let curve = model.geometry.curves[edge.curveID],
              let start = model.vertices[edge.startVertexID]?.point, let end = model.vertices[edge.endVertexID]?.point else {
            throw kernelError(.invalidInput, featureID: featureID, tolerance: tolerance,
                              "Each face drafted about a curve needs one of the pivot edges on it.")
        }
        switch curve {
        case .line, .analytic(.line): break
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): a curved pivot edge (a parting line along a curve)
            // would turn the face into a ruled surface about it, which is not built; such a curve
            // draft is refused. Production path: FaceDraftFeatureEvaluator with the curve method.
            // Complete only when a face drafted about a curved edge is verified by its volume.
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              "A curve draft turns faces about straight pivot edges.")
        }
        let direction = end - start
        guard abs(direction.dot(pull)) <= tolerance.angle * direction.length else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              "A curve draft's pivot edge must lie square to the pull direction.")
        }
        return .pivot(pull: pull, origin: start)
    }

    /// A planar face turned about its crossing with the neutral plane (square to `neutralNormal`)
    /// so that it makes `angle` with `pull`, leaning out as it runs against the pull: the plane
    /// through the pivot line whose normal N, square to the line, has N · pull = ±sin(angle),
    /// the nearest such turn to the face.
    private func tiltedSurface(
        of face: Face, surface: Surface3D, pull: Vector3D, neutralOrigin: Point3D, neutralNormal: Vector3D, angle: Double,
        featureID: FeatureID, model: BRepModel, tolerance: ModelingTolerance
    ) throws -> FaceSurfaceReplacementRebuilder.Replacement {
        guard let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "A surface draft turns planar faces.")
        }
        let normal = try plane.normal.normalized(tolerance: tolerance.distance)
        let outward = face.orientation == .forward ? normal : normal * -1
        let line = normal.cross(neutralNormal)
        guard line.length > tolerance.angle else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              "Face draft cannot turn a face parallel to the neutral plane.")
        }
        let axis = try line.normalized(tolerance: tolerance.distance)
        let points = try face.loops.flatMap { try model.orderedPoints(for: $0) }
        let center = Point3D.origin + points.reduce(Vector3D.zero) { $0 + ($1 - .origin) } / Double(points.count)
        let pivot = try pivotPoint(near: center, planeOrigin: plane.origin, planeNormal: normal, neutralOrigin: neutralOrigin,
                                   pull: neutralNormal, tolerance: tolerance)
        // N = cos φ e1 + sin φ e2 about the pivot line, e1 the face's outward side.
        let e1 = outward
        let e2 = axis.cross(e1)
        let (p1, p2) = (pull.dot(e1), pull.dot(e2))
        let reach = hypot(p1, p2)
        let target = sin(angle)
        guard reach > tolerance.angle, abs(target) <= reach else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              "The draft angle cannot be reached against this pull direction about the face's pivot line.")
        }
        let theta = atan2(p2, p1)
        var best: (turn: Double, normal: Vector3D)?
        for sign in [1.0, -1.0] {
            let spread = acos(max(-1, min(1, sign * target / reach)))
            for candidate in [theta + spread, theta - spread] {
                let turn = atan2(sin(candidate), cos(candidate))
                let drafted = e1 * cos(turn) + e2 * sin(turn)
                guard drafted.dot(e1) > 0 else { continue }
                // Running against the pull along the drafted face, it leans out for a positive angle.
                let against = pull * -1 - drafted * drafted.dot(pull * -1)
                let lean = against.dot(outward)
                if angle != 0, (lean > 0) != (angle > 0) { continue }
                if best.map({ abs(turn) < abs($0.turn) }) ?? true { best = (turn, drafted) }
            }
        }
        guard let best else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              "The draft angle cannot be reached against this pull direction about the face's pivot line.")
        }
        return try keepingOutwardSide(of: face, surface: surface, on: .plane(Plane3D(origin: pivot, normal: best.normal)),
                                      model: model, tolerance: tolerance)
    }

    /// A planar face drafted about the curved edge it shares with the reference: the ruled surface
    /// leaning out by the angle from the reference's outward normal at each point of the edge
    /// (`CurvedHingeDraftSurfaceBuilder`).
    private func curvedHingeSurface(
        of face: Face, surface: Surface3D, edgeID: EdgeID, reference: Face, referenceSurface: Surface3D,
        angle: Double, featureID: FeatureID, model: BRepModel, tolerance: ModelingTolerance
    ) throws -> FaceSurfaceReplacementRebuilder.Replacement {
        guard let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              "A face drafted about a curved edge of its reference is planar.")
        }
        guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID],
              let a = model.vertices[edge.startVertexID]?.point, let b = model.vertices[edge.endVertexID]?.point else {
            throw TopologyError.missingReference("A drafted face's hinge edge is missing.")
        }
        let (start, end) = try edge.trim.map { ($0.startParameter, $0.endParameter) }
            ?? (try curve.parameterProjection(of: a, tolerance: tolerance).parameter, try curve.parameterProjection(of: b, tolerance: tolerance).parameter)
        let normal = try plane.normal.normalized(tolerance: tolerance.distance)
        let outward = face.orientation == .forward ? normal : normal * -1
        // The face's size bounds how far the ruled lines and the hinge's carry-ons must reach.
        let points = try face.loops.flatMap { try model.orderedPoints(for: $0) }
        var reach = 0.0
        for p in points { for q in points { reach = max(reach, (p - q).length) } }
        let drafted = try CurvedHingeDraftSurfaceBuilder(tolerance: tolerance).construction(
            hinge: curve, start: start, end: end, reference: referenceSurface,
            referenceSign: reference.orientation == .forward ? 1 : -1, outward: outward, angle: angle, reach: reach
        )
        var replacement = try keepingOutwardSide(of: face, surface: surface, on: drafted.surface, model: model, tolerance: tolerance)
        if let receipt = drafted.receipt {
            replacement.hingeReceipt = FaceSurfaceReplacementRebuilder.HingeReceipt(
                edgeID: edgeID, referenceFaceID: reference.id, construction: receipt)
        }
        return replacement
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
    ) throws -> Hinge {
        guard let face = model.faces[faceID] else { throw TopologyError.missingReference("Face draft face is missing.") }
        func edgeIDs(of face: Face) throws -> Set<EdgeID> {
            try Set(face.loops.flatMap { loopID -> [EdgeID] in
                guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Face draft loop is missing.") }
                return loop.coedges.map(\.edgeID)
            })
        }
        let shared = try edgeIDs(of: face).intersection(edgeIDs(of: reference))
        let isStraight: (Edge) -> Bool = { edge in
            switch model.geometry.curves[edge.curveID] {
            case .line, .analytic(.line): true
            default: false
            }
        }
        guard shared.count == 1, let edgeID = shared.first, let edge = model.edges[edgeID],
              let start = model.vertices[edge.startVertexID]?.point, let end = model.vertices[edge.endVertexID]?.point else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              "A face drafted about a curved reference turns about the one edge it shares with it.")
        }
        // A curved shared edge: the face turns into the ruled surface leaning out from the
        // reference's normal along it.
        guard isStraight(edge) else { return .curve(edgeID) }
        let middle = start + (end - start) * 0.5
        let normals = try [start, middle, end].map { point -> Vector3D in
            let normal = try SurfaceFootResolver().foot(of: point, on: referenceSurface, tolerance: tolerance).normal
            return reference.orientation == .forward ? normal : normal * -1
        }
        // A reference turning along a straight edge leans the face differently along it: a ruled
        // surface as about a curved edge.
        guard normals.allSatisfy({ $0.cross(normals[0]).length <= tolerance.angle }) else { return .curve(edgeID) }
        return .pivot(pull: try normals[1].normalized(tolerance: tolerance.distance), origin: middle)
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

    private func targetEdgeID(
        _ stableReference: StableSubshapeReference,
        bodyScope: BodyTopologyScope,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EdgeID {
        let reference = try subshapeResolver.topologyReference(
            for: stableReference, model: context.brep, subshapes: context.subshapes, lineage: context.lineage, tolerance: context.tolerance
        )
        guard case let .edge(edgeID) = reference, bodyScope.references.contains(.edge(edgeID)) else {
            throw kernelError(.missingReference, featureID: featureID, subshapeID: stableReference.subshapeID, tolerance: context.tolerance,
                              "A curve draft's pivot must be an edge of the target body.")
        }
        return edgeID
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
