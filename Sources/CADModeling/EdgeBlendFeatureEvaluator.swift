import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct EdgeBlendFeatureEvaluator: Sendable {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving
    private let sewer: any BRepSewing

    package init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver(),
        sewer: any BRepSewing = DefaultBRepSewer()
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
        self.sewer = sewer
    }

    package func evaluateFillet(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .fillet(fillet) = feature.operation else {
            throw failure(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Fillet evaluator requires a fillet feature.")
        }
        guard fillet.edges.count == 1 else {
            throw failure(.unsupportedCapability, featureID: feature.id, tolerance: context.tolerance, "Current exact fillet supports one selected edge per feature.")
        }
        let radius = try resolvedRadius(fillet.radius, featureID: feature.id, context: context)
        let bodyID = try targetBodyID(fillet.target.featureID, featureID: feature.id, context: context)
        guard let body = context.brep.bodies[bodyID],
              body.kind == .solid,
              body.shellIDs.count == 1 else {
            throw failure(.unsupportedCapability, featureID: feature.id, tolerance: context.tolerance, "Current exact fillet requires one single-shell solid body.")
        }
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: bodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        let selected = fillet.edges[0]
        let edgeID = try targetEdgeID(selected, featureID: feature.id, context: context)
        let request = try request(
            featureID: feature.id,
            bodyID: bodyID,
            edgeID: edgeID,
            selectedSubshapeID: selected.subshapeID,
            radius: radius,
            context: context
        )
        let result = try sewer.sew(request, tolerance: context.tolerance)
        let model = try BRepBodyModelReplacer().replacing(
            bodyID: bodyID,
            with: result.bodyID,
            from: result.brep,
            in: context.brep
        )
        try model.validate(level: .volumetric, tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: result.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: result.lineage
        )
    }

    private func resolvedRadius(
        _ expression: CADExpression,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length,
              quantity.value.isFinite,
              quantity.value > context.tolerance.distance else {
            throw failure(.invalidInput, featureID: featureID, tolerance: context.tolerance, "Fillet radius must be a positive length above modeling tolerance.")
        }
        return quantity.value
    }

    private func targetBodyID(
        _ targetFeatureID: FeatureID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: targetFeatureID)
    }

    private func targetEdgeID(
        _ reference: StableSubshapeReference,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EdgeID {
        let topology = try subshapeResolver.topologyReference(
            for: reference,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .edge(edgeID) = topology else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                featureID: featureID,
                subshapeID: reference.subshapeID,
                tolerance: context.tolerance,
                message: "Fillet selection must resolve to an edge."
            )
        }
        return edgeID
    }

    private func request(
        featureID: FeatureID,
        bodyID: BodyID,
        edgeID: EdgeID,
        selectedSubshapeID: SubshapeID,
        radius: Double,
        context: EvaluationContext
    ) throws -> BRepSewingRequest {
        let model = context.brep
        guard let body = model.bodies[bodyID],
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              let edge = model.edges[edgeID],
              let startVertex = model.vertices[edge.startVertexID],
              let endVertex = model.vertices[edge.endVertexID] else {
            throw failure(.missingReference, featureID: featureID, tolerance: context.tolerance, "Fillet topology references are incomplete.")
        }
        let incidentFaceIDs = try shell.faceIDs.filter { try faceUses(edgeID: edgeID, faceID: $0, model: model) }
        guard incidentFaceIDs.count == 2 else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Fillet edge must have exactly two incident faces.")
        }
        let firstPlane = try orientedPlane(incidentFaceIDs[0], model: model, featureID: featureID, tolerance: context.tolerance)
        let secondPlane = try orientedPlane(incidentFaceIDs[1], model: model, featureID: featureID, tolerance: context.tolerance)
        guard abs(firstPlane.outward.dot(secondPlane.outward)) <= context.tolerance.angle else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Fillet incident faces must be perpendicular planes.")
        }
        let axisVector = endVertex.point - startVertex.point
        let length = axisVector.length
        let axis = try axisVector.normalized(tolerance: context.tolerance.distance)
        let firstInward = -firstPlane.outward
        let secondInward = -secondPlane.outward
        guard abs(axis.dot(firstInward)) <= context.tolerance.angle,
              abs(axis.dot(secondInward)) <= context.tolerance.angle else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Fillet edge must lie on both incident planes.")
        }
        let lowerCenter = startVertex.point + (firstInward + secondInward) * radius
        let upperCenter = endVertex.point + (firstInward + secondInward) * radius
        let cylinder = Surface3D.cylinder(Cylinder3D(origin: lowerCenter, axis: axis, radius: radius))
        let lowerCircle = Curve3D.circle(Circle3D(center: lowerCenter, normal: axis, radius: radius))
        let upperCircle = Curve3D.circle(Circle3D(center: upperCenter, normal: axis, radius: radius))
        let incidentParents = incidentFaceIDs.flatMap { subshapeIDs(for: .face($0), context: context) }
        var patches: [BRepSewingFacePatch] = []
        var lowerArc: ArcBoundary?
        var upperArc: ArcBoundary?
        for (faceIndex, faceID) in shell.faceIDs.enumerated() {
            let oriented = try orientedPlane(faceID, model: model, featureID: featureID, tolerance: context.tolerance)
            let polygon = try outerPolygon(faceID, model: model, featureID: featureID, tolerance: context.tolerance)
            let faceParents = subshapeIDs(for: .face(faceID), context: context)
            if faceID == incidentFaceIDs[0] || faceID == incidentFaceIDs[1] {
                let clippingNormal = faceID == incidentFaceIDs[0] ? secondInward : firstInward
                let clipped = simplified(
                    clip(polygon, origin: startVertex.point, normal: clippingNormal, offset: radius, tolerance: context.tolerance),
                    tolerance: context.tolerance
                )
                guard clipped.count >= 3 else {
                    throw failure(.topologyFailure, featureID: featureID, tolerance: context.tolerance, "Fillet radius removes an incident face.")
                }
                patches.append(try linePatch(
                    stableID: "source-face:\(faceIndex)",
                    plane: oriented,
                    vertices: clipped,
                    faceParents: faceParents,
                    edgeID: edgeID,
                    selectedSubshapeID: selectedSubshapeID,
                    model: model,
                    context: context
                ))
            } else if let cornerIndex = polygon.firstIndex(where: {
                $0.isApproximatelyEqual(to: startVertex.point, tolerance: context.tolerance.distance)
            }) {
                let rounded = try roundedCapPatch(
                    stableID: "source-face:\(faceIndex)",
                    plane: oriented,
                    polygon: polygon,
                    cornerIndex: cornerIndex,
                    circle: lowerCircle,
                    radius: radius,
                    faceParents: faceParents,
                    model: model,
                    context: context
                )
                patches.append(rounded.patch)
                lowerArc = rounded.arc
            } else if let cornerIndex = polygon.firstIndex(where: {
                $0.isApproximatelyEqual(to: endVertex.point, tolerance: context.tolerance.distance)
            }) {
                let rounded = try roundedCapPatch(
                    stableID: "source-face:\(faceIndex)",
                    plane: oriented,
                    polygon: polygon,
                    cornerIndex: cornerIndex,
                    circle: upperCircle,
                    radius: radius,
                    faceParents: faceParents,
                    model: model,
                    context: context
                )
                patches.append(rounded.patch)
                upperArc = rounded.arc
            } else {
                patches.append(try linePatch(
                    stableID: "source-face:\(faceIndex)",
                    plane: oriented,
                    vertices: polygon,
                    faceParents: faceParents,
                    edgeID: edgeID,
                    selectedSubshapeID: selectedSubshapeID,
                    model: model,
                    context: context
                ))
            }
        }
        guard let lowerArc, let upperArc else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Fillet requires planar cap faces at both edge endpoints.")
        }
        patches.append(try cylindricalPatch(
            surface: cylinder,
            lowerCircle: lowerCircle,
            upperCircle: upperCircle,
            lowerCapArc: lowerArc,
            upperCapArc: upperArc,
            height: length,
            selectedSubshapeID: selectedSubshapeID,
            faceParents: incidentParents,
            tolerance: context.tolerance
        ))
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(stableID: "shell:0", patches: patches)],
            bodyParentSubshapeIDs: subshapeIDs(for: .body(bodyID), context: context)
        )
    }

    private func linePatch(
        stableID: String,
        plane: OrientedPlane,
        vertices: [Point3D],
        faceParents: [SubshapeID],
        edgeID: EdgeID,
        selectedSubshapeID: SubshapeID,
        model: BRepModel,
        context: EvaluationContext
    ) throws -> BRepSewingFacePatch {
        let surface = Surface3D.plane(plane.plane)
        let edges = try vertices.indices.map { index in
            let start = vertices[index]
            let end = vertices[(index + 1) % vertices.count]
            return try lineEdge(
                stableID: "\(stableID):edge:\(index)",
                start: start,
                end: end,
                surface: surface,
                parents: sourceEdgeParents(
                    start: start,
                    end: end,
                    selectedEdgeID: edgeID,
                    selectedSubshapeID: selectedSubshapeID,
                    model: model,
                    context: context
                ),
                tolerance: context.tolerance
            )
        }
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: plane.orientation,
            loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
            parentSubshapeIDs: faceParents
        )
    }

    private func roundedCapPatch(
        stableID: String,
        plane: OrientedPlane,
        polygon: [Point3D],
        cornerIndex: Int,
        circle: Curve3D,
        radius: Double,
        faceParents: [SubshapeID],
        model: BRepModel,
        context: EvaluationContext
    ) throws -> RoundedCap {
        let rotated = polygon.indices.map { polygon[(cornerIndex + $0) % polygon.count] }
        let corner = rotated[0]
        let nextDirection = rotated[1] - corner
        let previousDirection = rotated[rotated.count - 1] - corner
        guard nextDirection.length > radius + context.tolerance.distance,
              previousDirection.length > radius + context.tolerance.distance else {
            throw failure(.unsupportedCapability, tolerance: context.tolerance, "Fillet radius must fit both endpoint edges.")
        }
        let tangentNext = corner + (try nextDirection.normalized(tolerance: context.tolerance.distance)) * radius
        let tangentPrevious = corner + (try previousDirection.normalized(tolerance: context.tolerance.distance)) * radius
        let boundary = [tangentNext] + Array(rotated.dropFirst()) + [tangentPrevious]
        let surface = Surface3D.plane(plane.plane)
        var edges = try (0..<(boundary.count - 1)).map { index in
            try lineEdge(
                stableID: "\(stableID):edge:\(index)",
                start: boundary[index],
                end: boundary[index + 1],
                surface: surface,
                parents: sourceEdgeParents(
                    start: boundary[index],
                    end: boundary[index + 1],
                    model: model,
                    context: context,
                    allowsSelectedFallback: false
                ),
                tolerance: context.tolerance
            )
        }
        let arc = try arcBoundary(
            curve: circle,
            start: tangentPrevious,
            end: tangentNext,
            surface: surface,
            tolerance: context.tolerance
        )
        edges.append(try circularEdge(
            stableID: "\(stableID):arc",
            curve: circle,
            start: arc.startParameter,
            end: arc.endParameter,
            surface: surface,
            parents: [],
            tolerance: context.tolerance
        ))
        return RoundedCap(
            patch: BRepSewingFacePatch(
                stableID: stableID,
                surface: surface,
                orientation: plane.orientation,
                loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
                parentSubshapeIDs: faceParents
            ),
            arc: arc
        )
    }

    private func cylindricalPatch(
        surface: Surface3D,
        lowerCircle: Curve3D,
        upperCircle: Curve3D,
        lowerCapArc: ArcBoundary,
        upperCapArc: ArcBoundary,
        height: Double,
        selectedSubshapeID: SubshapeID,
        faceParents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        let lowerStart = lowerCapArc.endPoint
        let lowerEnd = lowerCapArc.startPoint
        let startProjection = try surface.parameterProjection(of: lowerStart, tolerance: tolerance)
        let endProjection = try surface.parameterProjection(of: lowerEnd, tolerance: tolerance)
        let endU = nearestQuarterTurn(from: startProjection.u, to: endProjection.u)
        guard abs(abs(endU - startProjection.u) - Double.pi / 2.0) <= tolerance.angle * 16.0 else {
            throw failure(.topologyFailure, tolerance: tolerance, "Fillet cylinder must span one quarter turn.")
        }
        let lower = try circularEdge(
            stableID: "fillet:lower-arc",
            curve: lowerCircle,
            start: startProjection.u,
            end: endU,
            pcurve: .constantV(v: 0.0, uStart: startProjection.u, uEnd: endU),
            parents: [],
            tolerance: tolerance
        )
        let endLine = try axialEdge(
            stableID: "fillet:tangent:1",
            surface: surface,
            angle: endU,
            start: 0.0,
            end: height,
            parents: [selectedSubshapeID],
            tolerance: tolerance
        )
        let upper = try circularEdge(
            stableID: "fillet:upper-arc",
            curve: upperCircle,
            start: endU,
            end: startProjection.u,
            pcurve: .constantV(v: height, uStart: endU, uEnd: startProjection.u),
            parents: [],
            tolerance: tolerance
        )
        let startLine = try axialEdge(
            stableID: "fillet:tangent:0",
            surface: surface,
            angle: startProjection.u,
            start: height,
            end: 0.0,
            parents: [selectedSubshapeID],
            tolerance: tolerance
        )
        guard upperCapArc.startPoint.isApproximatelyEqual(to: upper.endPoint, tolerance: tolerance.distance),
              upperCapArc.endPoint.isApproximatelyEqual(to: upper.startPoint, tolerance: tolerance.distance) else {
            throw failure(.topologyFailure, tolerance: tolerance, "Fillet endpoint cap orientations are inconsistent.")
        }
        return BRepSewingFacePatch(
            stableID: "fillet:cylinder",
            surface: surface,
            orientation: .forward,
            loops: [BRepSewingLoop(
                stableID: "fillet:cylinder:outer",
                role: .outer,
                edges: [lower, endLine, upper, startLine]
            )],
            parentSubshapeIDs: faceParents
        )
    }

    private func lineEdge(
        stableID: String,
        start: Point3D,
        end: Point3D,
        surface: Surface3D,
        parents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let delta = end - start
        let length = delta.length
        let startUV = try surface.parameterProjection(of: start, tolerance: tolerance)
        let endUV = try surface.parameterProjection(of: end, tolerance: tolerance)
        return BRepSewingEdge(
            stableID: stableID,
            curve: .line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance))),
            startParameter: 0.0,
            endParameter: length,
            startPoint: start,
            endPoint: end,
            surfaceParameterCurve: .polyline([
                SurfaceParameter(u: startUV.u, v: startUV.v),
                SurfaceParameter(u: endUV.u, v: endUV.v),
            ]),
            parentSubshapeIDs: parents
        )
    }

    private func circularEdge(
        stableID: String,
        curve: Curve3D,
        start: Double,
        end: Double,
        surface: Surface3D? = nil,
        pcurve: SurfaceParameterCurve? = nil,
        parents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let resolvedPcurve: SurfaceParameterCurve
        if let pcurve {
            resolvedPcurve = pcurve
        } else if let surface {
            resolvedPcurve = try harmonicPcurve(curve: curve, surface: surface, start: start, end: end, tolerance: tolerance)
        } else {
            throw failure(.invalidInput, tolerance: tolerance, "Circular sewing edge requires a face-local pcurve.")
        }
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: start,
            endParameter: end,
            startPoint: try curve.point(at: start, tolerance: tolerance),
            endPoint: try curve.point(at: end, tolerance: tolerance),
            surfaceParameterCurve: resolvedPcurve,
            parentSubshapeIDs: parents
        )
    }

    private func axialEdge(
        stableID: String,
        surface: Surface3D,
        angle: Double,
        start: Double,
        end: Double,
        parents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        guard case let .cylinder(cylinder) = surface else {
            throw failure(.invalidInput, tolerance: tolerance, "Fillet axial edge requires a cylinder.")
        }
        let base = try surface.point(u: angle, v: 0.0, tolerance: tolerance)
        let curve = Curve3D.line(Line3D(origin: base, direction: cylinder.axis))
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: start,
            endParameter: end,
            startPoint: try curve.point(at: start, tolerance: tolerance),
            endPoint: try curve.point(at: end, tolerance: tolerance),
            surfaceParameterCurve: .constantU(u: angle, vStart: start, vEnd: end),
            parentSubshapeIDs: parents
        )
    }

    private func arcBoundary(
        curve: Curve3D,
        start: Point3D,
        end: Point3D,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ArcBoundary {
        let startProjection = try curve.parameterProjection(of: start, tolerance: tolerance)
        let endProjection = try curve.parameterProjection(of: end, tolerance: tolerance)
        let endParameter = nearestQuarterTurn(from: startProjection.parameter, to: endProjection.parameter)
        guard abs(abs(endParameter - startProjection.parameter) - Double.pi / 2.0) <= tolerance.angle * 16.0 else {
            throw failure(.topologyFailure, tolerance: tolerance, "Fillet cap arc must span one quarter turn.")
        }
        _ = try harmonicPcurve(
            curve: curve,
            surface: surface,
            start: startProjection.parameter,
            end: endParameter,
            tolerance: tolerance
        )
        return ArcBoundary(
            startPoint: start,
            endPoint: end,
            startParameter: startProjection.parameter,
            endParameter: endParameter
        )
    }

    private func harmonicPcurve(
        curve: Curve3D,
        surface: Surface3D,
        start: Double,
        end: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        guard case let .circle(circle) = curve else {
            throw failure(.invalidInput, tolerance: tolerance, "Fillet cap trim must be circular.")
        }
        let center = try surface.parameterProjection(of: circle.center, tolerance: tolerance)
        let cosine = try surface.parameterProjection(of: curve.point(at: 0.0, tolerance: tolerance), tolerance: tolerance)
        let sine = try surface.parameterProjection(of: curve.point(at: Double.pi / 2.0, tolerance: tolerance), tolerance: tolerance)
        return .harmonic(
            center: Point2D(x: center.u, y: center.v),
            cosine: Point2D(x: cosine.u - center.u, y: cosine.v - center.v),
            sine: Point2D(x: sine.u - center.u, y: sine.v - center.v),
            startParameter: start,
            endParameter: end
        )
    }

    private func nearestQuarterTurn(from start: Double, to end: Double) -> Double {
        var delta = end - start
        while delta > Double.pi { delta -= 2.0 * Double.pi }
        while delta < -Double.pi { delta += 2.0 * Double.pi }
        return start + delta
    }

    private func orientedPlane(
        _ faceID: FaceID,
        model: BRepModel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> OrientedPlane {
        guard let face = model.faces[faceID],
              case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "Current exact fillet requires planar source faces.")
        }
        return OrientedPlane(
            plane: plane,
            orientation: face.orientation,
            outward: face.orientation == .forward ? plane.normal : -plane.normal
        )
    }

    private func faceUses(edgeID: EdgeID, faceID: FaceID, model: BRepModel) throws -> Bool {
        guard let face = model.faces[faceID] else { throw TopologyError.missingReference("Missing face.") }
        return try face.loops.contains { loopID in
            guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing loop.") }
            return loop.edges.contains { $0.edgeID == edgeID }
        }
    }

    private func outerPolygon(
        _ faceID: FaceID,
        model: BRepModel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        guard let face = model.faces[faceID],
              face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "Current exact fillet requires one outer loop per source face.")
        }
        return try loop.edges.map { coedge in
            guard let edge = model.edges[coedge.edgeID] else { throw TopologyError.missingReference("Missing fillet source edge.") }
            let vertexID = coedge.orientation == .forward ? edge.startVertexID : edge.endVertexID
            guard let vertex = model.vertices[vertexID] else { throw TopologyError.missingReference("Missing fillet source vertex.") }
            return vertex.point
        }
    }

    private func clip(
        _ polygon: [Point3D],
        origin: Point3D,
        normal: Vector3D,
        offset: Double,
        tolerance: ModelingTolerance
    ) -> [Point3D] {
        var result: [Point3D] = []
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let startValue = (start - origin).dot(normal) - offset
            let endValue = (end - origin).dot(normal) - offset
            let startInside = startValue >= -tolerance.distance
            if startInside { result.append(start) }
            if startInside != (endValue >= -tolerance.distance) {
                let denominator = startValue - endValue
                if abs(denominator) > Double.ulpOfOne {
                    result.append(start + (end - start) * (startValue / denominator))
                }
            }
        }
        return result
    }

    private func simplified(_ polygon: [Point3D], tolerance: ModelingTolerance) -> [Point3D] {
        var result: [Point3D] = []
        for point in polygon where result.last?.isApproximatelyEqual(to: point, tolerance: tolerance.distance) != true {
            result.append(point)
        }
        if result.count > 1, result[0].isApproximatelyEqual(to: result[result.count - 1], tolerance: tolerance.distance) {
            result.removeLast()
        }
        return result
    }

    private func sourceEdgeParents(
        start: Point3D,
        end: Point3D,
        selectedEdgeID: EdgeID? = nil,
        selectedSubshapeID: SubshapeID? = nil,
        model: BRepModel,
        context: EvaluationContext,
        allowsSelectedFallback: Bool = true
    ) -> [SubshapeID] {
        for edge in model.edges.values {
            guard let first = model.vertices[edge.startVertexID]?.point,
                  let second = model.vertices[edge.endVertexID]?.point,
                  point(start, on: first, second, tolerance: context.tolerance),
                  point(end, on: first, second, tolerance: context.tolerance) else { continue }
            let parents = subshapeIDs(for: .edge(edge.id), context: context)
            if parents.isEmpty == false { return parents }
        }
        guard allowsSelectedFallback,
              let selectedEdgeID,
              let selectedSubshapeID,
              let selected = model.edges[selectedEdgeID],
              let first = model.vertices[selected.startVertexID]?.point,
              let second = model.vertices[selected.endVertexID]?.point else { return [] }
        let selectedDirection = second - first
        let candidateDirection = end - start
        let scale = max(selectedDirection.length * candidateDirection.length, Double.leastNonzeroMagnitude)
        return selectedDirection.cross(candidateDirection).length <= context.tolerance.angle * scale
            ? [selectedSubshapeID]
            : []
    }

    private func point(
        _ point: Point3D,
        on start: Point3D,
        _ end: Point3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        let segment = end - start
        let length = segment.length
        guard length > tolerance.distance else { return false }
        let offset = point - start
        guard segment.cross(offset).length <= tolerance.distance * length else { return false }
        let parameter = offset.dot(segment) / (length * length)
        return parameter >= -tolerance.distance / length && parameter <= 1.0 + tolerance.distance / length
    }

    private func subshapeIDs(for reference: TopologyReference, context: EvaluationContext) -> [SubshapeID] {
        context.subshapeIDs(for: reference)
    }

    package func evaluateG2(
        feature: FeatureNode,
        blend: G2BlendFeature,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard blend.edges.count == 1 else {
            throw failure(.unsupportedCapability, featureID: feature.id, tolerance: context.tolerance, "Current exact G2 blend supports one selected edge per feature.")
        }
        let quantity = try resolver.evaluate(blend.distance, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length,
              quantity.value.isFinite,
              quantity.value > context.tolerance.distance else {
            throw failure(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "G2 blend distance must be a positive length above modeling tolerance.")
        }
        let bodyID = try targetBodyID(blend.target.featureID, featureID: feature.id, context: context)
        guard let body = context.brep.bodies[bodyID],
              body.kind == .solid,
              body.shellIDs.count == 1 else {
            throw failure(.unsupportedCapability, featureID: feature.id, tolerance: context.tolerance, "Current exact G2 blend requires one single-shell solid body.")
        }
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: bodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        let selected = blend.edges[0]
        let edgeID = try targetEdgeID(selected, featureID: feature.id, context: context)
        let request = try g2Request(
            featureID: feature.id,
            bodyID: bodyID,
            edgeID: edgeID,
            selectedSubshapeID: selected.subshapeID,
            distance: quantity.value,
            context: context
        )
        let result = try sewer.sew(request, tolerance: context.tolerance)
        let model = try BRepBodyModelReplacer().replacing(
            bodyID: bodyID,
            with: result.bodyID,
            from: result.brep,
            in: context.brep
        )
        try model.validate(level: .volumetric, tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: result.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: result.lineage
        )
    }

    private func g2Request(
        featureID: FeatureID,
        bodyID: BodyID,
        edgeID: EdgeID,
        selectedSubshapeID: SubshapeID,
        distance: Double,
        context: EvaluationContext
    ) throws -> BRepSewingRequest {
        let model = context.brep
        guard let body = model.bodies[bodyID],
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              let edge = model.edges[edgeID],
              let startVertex = model.vertices[edge.startVertexID],
              let endVertex = model.vertices[edge.endVertexID] else {
            throw failure(.missingReference, featureID: featureID, tolerance: context.tolerance, "G2 blend topology references are incomplete.")
        }
        let incidentFaceIDs = try shell.faceIDs.filter { try faceUses(edgeID: edgeID, faceID: $0, model: model) }
        guard incidentFaceIDs.count == 2 else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "G2 blend edge must have exactly two incident faces.")
        }
        let firstPlane = try orientedPlane(incidentFaceIDs[0], model: model, featureID: featureID, tolerance: context.tolerance)
        let secondPlane = try orientedPlane(incidentFaceIDs[1], model: model, featureID: featureID, tolerance: context.tolerance)
        guard abs(firstPlane.outward.dot(secondPlane.outward)) <= context.tolerance.angle else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "G2 blend incident faces must be perpendicular planes.")
        }
        let axisVector = endVertex.point - startVertex.point
        let height = axisVector.length
        let axis = try axisVector.normalized(tolerance: context.tolerance.distance)
        let firstInward = -firstPlane.outward
        let secondInward = -secondPlane.outward
        let lowerControlPoints = quinticControlPoints(
            corner: startVertex.point,
            firstInward: firstInward,
            secondInward: secondInward,
            distance: distance
        )
        let upperControlPoints = lowerControlPoints.map { $0 + axis * height }
        let knots = Array(repeating: 0.0, count: 6) + Array(repeating: 1.0, count: 6)
        let lowerCurve = BSplineCurve3D(degree: 5, knots: knots, controlPoints: lowerControlPoints)
        let upperCurve = BSplineCurve3D(degree: 5, knots: knots, controlPoints: upperControlPoints)
        let blendDefinition = BSplineSurface3D(
            uDegree: 5,
            vDegree: 1,
            uKnots: knots,
            vKnots: [0.0, 0.0, height, height],
            controlPoints: [lowerControlPoints, upperControlPoints]
        )
        try lowerCurve.validate(tolerance: context.tolerance)
        try upperCurve.validate(tolerance: context.tolerance)
        try blendDefinition.validate(tolerance: context.tolerance)
        let blendSurface = Surface3D.bSpline(blendDefinition)
        let incidentParents = incidentFaceIDs.flatMap { subshapeIDs(for: .face($0), context: context) }
        var patches: [BRepSewingFacePatch] = []
        var lowerCap: BSplineCapBoundary?
        var upperCap: BSplineCapBoundary?
        for (faceIndex, faceID) in shell.faceIDs.enumerated() {
            let oriented = try orientedPlane(faceID, model: model, featureID: featureID, tolerance: context.tolerance)
            let polygon = try outerPolygon(faceID, model: model, featureID: featureID, tolerance: context.tolerance)
            let faceParents = subshapeIDs(for: .face(faceID), context: context)
            if faceID == incidentFaceIDs[0] || faceID == incidentFaceIDs[1] {
                let clippingNormal = faceID == incidentFaceIDs[0] ? secondInward : firstInward
                let clipped = simplified(
                    clip(polygon, origin: startVertex.point, normal: clippingNormal, offset: distance, tolerance: context.tolerance),
                    tolerance: context.tolerance
                )
                guard clipped.count >= 3 else {
                    throw failure(.topologyFailure, featureID: featureID, tolerance: context.tolerance, "G2 blend distance removes an incident face.")
                }
                patches.append(try linePatch(
                    stableID: "source-face:\(faceIndex)",
                    plane: oriented,
                    vertices: clipped,
                    faceParents: faceParents,
                    edgeID: edgeID,
                    selectedSubshapeID: selectedSubshapeID,
                    model: model,
                    context: context
                ))
            } else if let cornerIndex = polygon.firstIndex(where: {
                $0.isApproximatelyEqual(to: startVertex.point, tolerance: context.tolerance.distance)
            }) {
                let cap = try g2CapPatch(
                    stableID: "source-face:\(faceIndex)",
                    plane: oriented,
                    polygon: polygon,
                    cornerIndex: cornerIndex,
                    curve: lowerCurve,
                    distance: distance,
                    faceParents: faceParents,
                    model: model,
                    context: context
                )
                patches.append(cap.patch)
                lowerCap = cap.boundary
            } else if let cornerIndex = polygon.firstIndex(where: {
                $0.isApproximatelyEqual(to: endVertex.point, tolerance: context.tolerance.distance)
            }) {
                let cap = try g2CapPatch(
                    stableID: "source-face:\(faceIndex)",
                    plane: oriented,
                    polygon: polygon,
                    cornerIndex: cornerIndex,
                    curve: upperCurve,
                    distance: distance,
                    faceParents: faceParents,
                    model: model,
                    context: context
                )
                patches.append(cap.patch)
                upperCap = cap.boundary
            } else {
                patches.append(try linePatch(
                    stableID: "source-face:\(faceIndex)",
                    plane: oriented,
                    vertices: polygon,
                    faceParents: faceParents,
                    edgeID: edgeID,
                    selectedSubshapeID: selectedSubshapeID,
                    model: model,
                    context: context
                ))
            }
        }
        guard let lowerCap, let upperCap else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "G2 blend requires planar cap faces at both edge endpoints.")
        }
        patches.append(try g2SurfacePatch(
            surface: blendSurface,
            definition: blendDefinition,
            lowerCurve: lowerCurve,
            upperCurve: upperCurve,
            lowerCap: lowerCap,
            upperCap: upperCap,
            height: height,
            selectedSubshapeID: selectedSubshapeID,
            faceParents: incidentParents,
            firstOutward: firstPlane.outward,
            tolerance: context.tolerance
        ))
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(stableID: "shell:0", patches: patches)],
            bodyParentSubshapeIDs: subshapeIDs(for: .body(bodyID), context: context)
        )
    }

    private func quinticControlPoints(
        corner: Point3D,
        firstInward: Vector3D,
        secondInward: Vector3D,
        distance: Double
    ) -> [Point3D] {
        let first = corner + secondInward * distance
        let second = corner + firstInward * distance
        let handle = distance / 3.0
        let firstHandle = first + secondInward * (-handle)
        let firstCurvature = first + secondInward * (-2.0 * handle)
        let secondCurvature = second + firstInward * (-2.0 * handle)
        let secondHandle = second + firstInward * (-handle)
        return [
            first,
            firstHandle,
            firstCurvature,
            secondCurvature,
            secondHandle,
            second,
        ]
    }

    private func g2CapPatch(
        stableID: String,
        plane: OrientedPlane,
        polygon: [Point3D],
        cornerIndex: Int,
        curve: BSplineCurve3D,
        distance: Double,
        faceParents: [SubshapeID],
        model: BRepModel,
        context: EvaluationContext
    ) throws -> G2Cap {
        let rotated = polygon.indices.map { polygon[(cornerIndex + $0) % polygon.count] }
        let corner = rotated[0]
        let nextDirection = rotated[1] - corner
        let previousDirection = rotated[rotated.count - 1] - corner
        guard nextDirection.length > distance + context.tolerance.distance,
              previousDirection.length > distance + context.tolerance.distance else {
            throw failure(.unsupportedCapability, tolerance: context.tolerance, "G2 blend distance must fit both endpoint edges.")
        }
        let tangentNext = corner + (try nextDirection.normalized(tolerance: context.tolerance.distance)) * distance
        let tangentPrevious = corner + (try previousDirection.normalized(tolerance: context.tolerance.distance)) * distance
        let boundary = [tangentNext] + Array(rotated.dropFirst()) + [tangentPrevious]
        let surface = Surface3D.plane(plane.plane)
        var edges = try (0..<(boundary.count - 1)).map { index in
            try lineEdge(
                stableID: "\(stableID):edge:\(index)",
                start: boundary[index],
                end: boundary[index + 1],
                surface: surface,
                parents: sourceEdgeParents(
                    start: boundary[index],
                    end: boundary[index + 1],
                    model: model,
                    context: context,
                    allowsSelectedFallback: false
                ),
                tolerance: context.tolerance
            )
        }
        let curveStart = curve.controlPoints[0]
        let forward = tangentPrevious.isApproximatelyEqual(to: curveStart, tolerance: context.tolerance.distance)
        let startParameter = forward ? 0.0 : 1.0
        let endParameter = forward ? 1.0 : 0.0
        let parameterCurve = try planarParameterCurve(
            curve: curve,
            surface: surface,
            reversed: forward == false,
            tolerance: context.tolerance
        )
        edges.append(BRepSewingEdge(
            stableID: "\(stableID):g2",
            curve: .bSpline(curve),
            startParameter: startParameter,
            endParameter: endParameter,
            startPoint: tangentPrevious,
            endPoint: tangentNext,
            surfaceParameterCurve: .bSpline(parameterCurve)
        ))
        return G2Cap(
            patch: BRepSewingFacePatch(
                stableID: stableID,
                surface: surface,
                orientation: plane.orientation,
                loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
                parentSubshapeIDs: faceParents
            ),
            boundary: BSplineCapBoundary(startPoint: tangentPrevious, endPoint: tangentNext)
        )
    }

    private func planarParameterCurve(
        curve: BSplineCurve3D,
        surface: Surface3D,
        reversed: Bool,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve2D {
        let controlPoints = try curve.controlPoints.map { point in
            let projection = try surface.parameterProjection(of: point, tolerance: tolerance)
            return Point2D(x: projection.u, y: projection.v)
        }
        let result = BSplineCurve2D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: controlPoints,
            weights: curve.weights
        )
        return reversed ? try result.reversed(tolerance: tolerance) : result
    }

    private func g2SurfacePatch(
        surface: Surface3D,
        definition: BSplineSurface3D,
        lowerCurve: BSplineCurve3D,
        upperCurve: BSplineCurve3D,
        lowerCap: BSplineCapBoundary,
        upperCap: BSplineCapBoundary,
        height: Double,
        selectedSubshapeID: SubshapeID,
        faceParents: [SubshapeID],
        firstOutward: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        let lowerForward = lowerCap.endPoint.isApproximatelyEqual(to: lowerCurve.controlPoints[0], tolerance: tolerance.distance)
        let lowerStart = lowerForward ? 0.0 : 1.0
        let lowerEnd = lowerForward ? 1.0 : 0.0
        let upperStart = lowerEnd
        let upperEnd = lowerStart
        let expectedUpperStart = try upperCurve.point(at: upperStart, tolerance: tolerance)
        let expectedUpperEnd = try upperCurve.point(at: upperEnd, tolerance: tolerance)
        guard upperCap.endPoint.isApproximatelyEqual(to: expectedUpperStart, tolerance: tolerance.distance),
              upperCap.startPoint.isApproximatelyEqual(to: expectedUpperEnd, tolerance: tolerance.distance) else {
            throw failure(.topologyFailure, tolerance: tolerance, "G2 blend cap orientations are inconsistent.")
        }
        let lower = BRepSewingEdge(
            stableID: "g2:lower",
            curve: .bSpline(lowerCurve),
            startParameter: lowerStart,
            endParameter: lowerEnd,
            startPoint: try lowerCurve.point(at: lowerStart, tolerance: tolerance),
            endPoint: try lowerCurve.point(at: lowerEnd, tolerance: tolerance),
            surfaceParameterCurve: .constantV(v: 0.0, uStart: lowerStart, uEnd: lowerEnd)
        )
        let endLine = try g2AxialEdge(
            stableID: "g2:tangent:1",
            surface: surface,
            u: lowerEnd,
            start: 0.0,
            end: height,
            parents: [selectedSubshapeID],
            tolerance: tolerance
        )
        let upper = BRepSewingEdge(
            stableID: "g2:upper",
            curve: .bSpline(upperCurve),
            startParameter: upperStart,
            endParameter: upperEnd,
            startPoint: try upperCurve.point(at: upperStart, tolerance: tolerance),
            endPoint: try upperCurve.point(at: upperEnd, tolerance: tolerance),
            surfaceParameterCurve: .constantV(v: height, uStart: upperStart, uEnd: upperEnd)
        )
        let startLine = try g2AxialEdge(
            stableID: "g2:tangent:0",
            surface: surface,
            u: lowerStart,
            start: height,
            end: 0.0,
            parents: [selectedSubshapeID],
            tolerance: tolerance
        )
        let normal = try definition.normal(u: 0.0, v: height * 0.5, tolerance: tolerance)
        let orientation: Orientation = normal.dot(firstOutward) >= 0.0 ? .forward : .reversed
        return BRepSewingFacePatch(
            stableID: "g2:surface",
            surface: surface,
            orientation: orientation,
            loops: [BRepSewingLoop(
                stableID: "g2:surface:outer",
                role: .outer,
                edges: [lower, endLine, upper, startLine]
            )],
            parentSubshapeIDs: faceParents
        )
    }

    private func g2AxialEdge(
        stableID: String,
        surface: Surface3D,
        u: Double,
        start: Double,
        end: Double,
        parents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let startPoint = try surface.point(u: u, v: start, tolerance: tolerance)
        let endPoint = try surface.point(u: u, v: end, tolerance: tolerance)
        let delta = endPoint - startPoint
        return BRepSewingEdge(
            stableID: stableID,
            curve: .line(Line3D(origin: startPoint, direction: try delta.normalized(tolerance: tolerance.distance))),
            startParameter: 0.0,
            endParameter: delta.length,
            startPoint: startPoint,
            endPoint: endPoint,
            surfaceParameterCurve: .constantU(u: u, vStart: start, vEnd: end),
            parentSubshapeIDs: parents
        )
    }

    private func failure(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }

    private struct OrientedPlane {
        let plane: Plane3D
        let orientation: Orientation
        let outward: Vector3D
    }

    private struct ArcBoundary {
        let startPoint: Point3D
        let endPoint: Point3D
        let startParameter: Double
        let endParameter: Double
    }

    private struct RoundedCap {
        let patch: BRepSewingFacePatch
        let arc: ArcBoundary
    }

    private struct BSplineCapBoundary {
        let startPoint: Point3D
        let endPoint: Point3D
    }

    private struct G2Cap {
        let patch: BRepSewingFacePatch
        let boundary: BSplineCapBoundary
    }
}
