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
    /// Sewing and Boolean application, for a face filled up to an oblique wall: the prism up to
    /// the wall's plane sewn and joined to the body.
    private let sewer: (any BRepSewing)?
    private let applicator: (any BooleanOperationApplying)?

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver(),
        faceExtruder: (any FeatureEvaluating)? = nil,
        sewer: (any BRepSewing)? = nil,
        applicator: (any BooleanOperationApplying)? = nil
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
        self.faceExtruder = faceExtruder
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
        let replacedSubshapeIDs = try bodyScope.subshapeIDs(in: context.subshapes)
        // Grow (Moving or Fixed): planar faces facing one way pushed out, each past a parallel
        // wall of its body facing the same way, fill up to their walls (each face extruded and
        // joined), then Moving pushes the walls they became part of on by the rest of the distance.
        // Under Fixed a polygonal face running into an oblique wall fills up to that wall's plane.
        // FIXME(INCOMPLETE_IMPLEMENTATION): Moving into an oblique wall, faces with curved edges
        // into one, curved faces, faces facing different ways and an adjacent angle take the
        // in-place re-solve below, which fails explicitly where the faces around cannot follow.
        // Production path: Push Face (FaceOffsetFeatureEvaluator) with Grow Moving or Fixed.
        // Complete only when those faces grow into the walls they run into, verified by a face
        // pushed into an oblique wall under Moving (how the wall moves is not settled by the
        // official page).
        let pushedPlanes = try parallelPlanes(of: faceIDs, model: context.brep, tolerance: context.tolerance)
        if offset.grow != .none, adjacentAngle == 0, distance > 0, let pushedPlanes {
            let gaps = try faceIDs.indices.map { index in
                try wallGap(from: faceIDs[index], plane: pushedPlanes[index], distance: distance, bodyScope: bodyScope,
                            model: context.brep, tolerance: context.tolerance)
            }
            if gaps.allSatisfy({ $0 != nil }) {
                return try grownToWalls(offset, feature: feature, planes: pushedPlanes, gaps: gaps.compactMap { $0 },
                                        distance: distance, removing: replacedSubshapeIDs, context: context)
            }
            if offset.grow == .fixed,
               let fills = try obliqueFills(of: faceIDs, outward: pushedPlanes[0].outward, distance: distance,
                                            bodyScope: bodyScope, model: context.brep, tolerance: context.tolerance) {
                return try filled(fills, axis: pushedPlanes[0].outward, bodyID: bodyID, featureID: feature.id, context: context)
            }
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
        // The faces around re-solved in place; under None planar faces facing one way whose
        // neighbours cannot follow them keep going by themselves: each extruded and joined to its
        // body (outward) or cut from it (inward).
        do {
            try FaceSurfaceReplacementRebuilder().replace(
                replacements, bodyID: bodyID, featureID: feature.id, model: &model, tolerance: context.tolerance
            )
            try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: context.tolerance)
            let isSolid = model.bodies[bodyID]?.kind == .solid
            try model.validate(level: isSolid ? .volumetric : .exact, tolerance: context.tolerance)
        } catch {
            guard offset.grow == .none, adjacentAngle == 0, let pushedPlanes else { throw error }
            return try extrusions(offset, feature: feature, extents: faceIDs.map { _ in abs(distance) },
                                  inward: distance < 0 ? pushedPlanes[0].outward * -1 : nil, context: context)
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

    /// For each pushed face, its corners and the oblique wall it runs into: a planar face of its
    /// body facing forward but not parallel, whose plane every corner reaches along `outward`
    /// short of the distance, the nearest such. Nil unless every face is a polygon (straight edges,
    /// no holes) with such a wall.
    // FIXME(INCOMPLETE_IMPLEMENTATION): Production Fixed planar Grow selects supporting
    // walls from corner reach. Whole finite-wall coverage, curved boundaries and every
    // intervening material contact remain required before the general E4 gate closes.
    private func obliqueFills(of faceIDs: [FaceID], outward: Vector3D, distance: Double, bodyScope: BodyTopologyScope,
                              model: BRepModel, tolerance: ModelingTolerance)
        throws -> [(corners: [Point3D], wallOrigin: Point3D, wallNormal: Vector3D)]? {
        var fills: [(corners: [Point3D], wallOrigin: Point3D, wallNormal: Vector3D)] = []
        for faceID in faceIDs {
            guard let face = model.faces[faceID], face.loops.count == 1, let loop = model.loops[face.loops[0]],
                  try loop.coedges.allSatisfy({ coedge in
                      guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID] else {
                          throw TopologyError.missingReference("Push Face's edge is missing.")
                      }
                      switch curve {
                      case .line, .analytic(.line): return true
                      default: return false
                      }
                  }) else { return nil }
            let corners = try model.orderedPoints(for: face.loops[0])
            var nearest: (reach: Double, origin: Point3D, normal: Vector3D)?
            for case let .face(otherID) in bodyScope.references where faceIDs.contains(otherID) == false {
                guard let wall = try outwardPlane(of: otherID, model: model, tolerance: tolerance) else { continue }
                let slope = outward.dot(wall.outward)
                guard slope > tolerance.angle, slope < 1 - tolerance.angle else { continue }
                let reaches = corners.map { (wall.origin - $0).dot(wall.outward) / slope }
                guard let shortest = reaches.min(), let longest = reaches.max(), shortest > tolerance.distance,
                      longest < distance - tolerance.distance else { continue }
                if nearest.map({ longest < $0.reach }) ?? true { nearest = (longest, wall.origin, wall.outward) }
            }
            guard let nearest else { return nil }
            fills.append((corners, nearest.origin, nearest.normal))
        }
        return fills
    }

    /// Fixed into oblique walls: each face's prism up to its wall's plane sewn and joined to the
    /// body in turn, the last under the feature.
    private func filled(_ fills: [(corners: [Point3D], wallOrigin: Point3D, wallNormal: Vector3D)], axis: Vector3D, bodyID: BodyID,
                        featureID: FeatureID, context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        guard let sewer, let applicator else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                              "Push Face's Grow into an oblique wall needs sewing and a Boolean applicator.")
        }
        var stages = FeatureEvaluationStages(context)
        var target = bodyID
        for (index, fill) in fills.enumerated() {
            let staged = stages.context
            let last = index == fills.count - 1
            let stageID = last ? featureID : featureEvaluationStageID(featureID: featureID, domain: .pushFaceGrow, ordinal: UInt64(index + 1))
            let toolFeatureID = featureEvaluationStageID(featureID: featureID, domain: .pushFaceGrow, ordinal: (UInt64(index + 1) << 32) | 1)
            let request = try PolygonPrismRequestBuilder(tolerance: tolerance).request(
                featureID: toolFeatureID, polygon: fill.corners, axis: axis, capOrigin: fill.wallOrigin, capNormal: fill.wallNormal,
                stablePrefix: "pushGrow\(index)"
            )
            let tool = try sewer.sew(request, tolerance: tolerance)
            let toolBodyIDs = Set(tool.subshapes.values.compactMap { reference -> BodyID? in
                guard case let .body(id) = reference else { return nil }
                return id
            })
            guard toolBodyIDs.count == 1, let toolBodyID = toolBodyIDs.first else {
                throw kernelError(.topologyFailure, featureID: featureID, tolerance: tolerance, "A pushed face's fill is not one body.")
            }
            var subshapes = staged.subshapes.entries
            subshapes.merge(tool.subshapes) { current, _ in current }
            var lineage = staged.lineage
            lineage.merge(tool.lineage) { current, _ in current }
            var step = try applicator.apply(
                operation: .union, targetBodyIDs: [target], toolBodyID: toolBodyID, keepTools: false, featureID: stageID,
                model: try BRepModelCombiner().combined([staged.brep, tool.brep]), subshapes: subshapes,
                toolSubshapes: tool.subshapes, inputLineage: lineage, tolerance: tolerance
            )
            // The fill was never published, so its identities are neither removed nor parents.
            let toolSubshapeIDs = Set(tool.subshapes.keys)
            step.removedSubshapeIDs.subtract(toolSubshapeIDs)
            step.lineage = step.lineage.mapValues { entry in
                TopologyLineage(output: entry.output, parents: entry.parents.filter { !toolSubshapeIDs.contains($0) }, relation: entry.relation)
            }.withRelationsDerivedFromParents()
            if last { return fills.count == 1 ? step : try stages.publish(step, featureID: featureID) }
            stages.apply(step)
            target = try stages.publishedBody(of: step, featureID: featureID, what: "Filling a pushed face")
        }
        throw kernelError(.invalidInput, featureID: featureID, tolerance: tolerance, "Push Face pushes a face.")
    }

    /// The planes of planar faces all facing one way (outward normals within the angle
    /// tolerance); nil when any face is curved or faces another way.
    private func parallelPlanes(of faceIDs: [FaceID], model: BRepModel, tolerance: ModelingTolerance)
        throws -> [(origin: Point3D, surfaceNormal: Vector3D, outward: Vector3D)]? {
        var planes: [(origin: Point3D, surfaceNormal: Vector3D, outward: Vector3D)] = []
        for faceID in faceIDs {
            guard let plane = try outwardPlane(of: faceID, model: model, tolerance: tolerance) else { return nil }
            if let first = planes.first, plane.outward.dot(first.outward) < 1 - tolerance.angle { return nil }
            planes.append(plane)
        }
        return planes.isEmpty ? nil : planes
    }

    /// The pushed faces extruded by their `extents` (outward, joined; inward, cut) with the
    /// Extrude its evaluator was given. One face is extruded as its face section; several are read
    /// as profiles where they are, then extruded one after another, each joined to (or cut from)
    /// the body the one before left.
    private func extrusions(_ offset: FaceOffsetFeature, feature: FeatureNode, extents: [Double], inward: Vector3D?,
                            context: EvaluationContext) throws -> EvaluationResult {
        guard let faceExtruder else {
            throw kernelError(.unsupportedCapability, featureID: feature.id, tolerance: context.tolerance,
                              "Push Face's Grow needs an Extrude to carry the face past its neighbours.")
        }
        func node(_ id: FeatureID, section: SectionReference, extent: Double, target: FeatureID) -> FeatureNode {
            FeatureNode(id: id, name: feature.name, operation: .extrude(ExtrudeFeature(
                section: section, distance: .constant(.length(extent, unit: .meter)),
                direction: inward.map { .vector($0) } ?? .normal, operation: inward == nil ? .union : .difference,
                targets: [BooleanTargetReference(featureID: target)], resultKind: .solid
            )), outputs: feature.outputs)
        }
        let faceSections = offset.faces.map {
            FaceSectionReference(featureID: offset.target.featureID, face: $0, bodyRole: .body)
        }
        if faceSections.count == 1 {
            return try faceExtruder.evaluate(
                feature: node(feature.id, section: .face(faceSections[0]), extent: extents[0], target: offset.target.featureID),
                context: context
            )
        }
        // Every face is read before any extrusion changes the body.
        let profiles = try faceSections.map {
            try FaceSectionProfileResolver(subshapeResolver: subshapeResolver).profile(for: $0, context: context, featureID: feature.id)
        }
        var stages = FeatureEvaluationStages(context)
        var target = offset.target.featureID
        for (index, profile) in profiles.enumerated() {
            let last = index == profiles.count - 1
            let stageID = last ? feature.id : featureEvaluationStageID(featureID: feature.id, domain: .pushFaceGrow, ordinal: UInt64(index + 1))
            let profileID = featureEvaluationStageID(featureID: feature.id, domain: .pushFaceGrow, ordinal: UInt64(index + 1) << 32)
            var stagedContext = stages.context
            stagedContext.profiles[profileID] = [Profile(sourceFeatureID: profileID, plane: profile.plane,
                                                         outerLoop: profile.outerLoop, innerLoops: profile.innerLoops)]
            let result = try faceExtruder.evaluate(
                feature: node(stageID, section: .profile(ProfileReference(featureID: profileID)), extent: extents[index], target: target),
                context: stagedContext
            )
            if last { return try stages.publish(result, featureID: feature.id) }
            stages.apply(result)
            target = stageID
        }
        throw kernelError(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Push Face pushes a face.")
    }

    /// Moving or Fixed into walls: each face filled up to its wall (extruded by its gap and
    /// joined); under Moving the faces they then share with their walls pushed on by the rest.
    private func grownToWalls(_ offset: FaceOffsetFeature, feature: FeatureNode,
                              planes: [(origin: Point3D, surfaceNormal: Vector3D, outward: Vector3D)],
                              gaps: [Double], distance: Double, removing replacedSubshapeIDs: Set<SubshapeID>,
                              context: EvaluationContext) throws -> EvaluationResult {
        let filled = try extrusions(offset, feature: feature, extents: gaps, inward: nil, context: context)
        guard offset.grow == .moving else { return filled }
        var model = filled.brep
        guard let bodyID = filled.subshapes.compactMap({ key, value -> BodyID? in
            guard key.featureID == feature.id, case let .body(id) = value else { return nil }
            return id
        }).first else {
            throw TopologyError.missingReference("Push Face's filled body is missing.")
        }
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        let outward = planes[0].outward
        // Each wall moves on by what is left of the distance past the gap that reached it.
        var rests: [FaceID: Double] = [:]
        for case let .face(faceID) in scope.references {
            guard let wall = try outwardPlane(of: faceID, model: model, tolerance: context.tolerance),
                  wall.outward.dot(outward) >= 1 - context.tolerance.angle else { continue }
            for (plane, gap) in zip(planes, gaps)
            where abs((wall.origin - plane.origin).dot(outward) - gap) <= context.tolerance.distance {
                rests[faceID] = distance - gap
            }
        }
        guard rests.isEmpty == false else {
            throw kernelError(.topologyFailure, featureID: feature.id, tolerance: context.tolerance, "Push Face's filled face did not join its wall.")
        }
        var replacements: [FaceID: FaceSurfaceReplacementRebuilder.Replacement] = [:]
        for (faceID, rest) in rests {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Push Face's wall is missing.")
            }
            replacements[faceID] = FaceSurfaceReplacementRebuilder.Replacement(
                surface: try FaceSurfaceOffsetter().offset(surface, orientation: face.orientation, by: rest, tolerance: context.tolerance),
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
