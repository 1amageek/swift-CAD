import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct SetbackCornerFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving
    private let sewer: any BRepSewing

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver(),
        sewer: any BRepSewing = DefaultBRepSewer()
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
        self.sewer = sewer
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
        let result = try evaluateUnvalidated(feature: feature, context: context)
        return try ValidatedFeatureEvaluation(
            validating: result,
            tolerance: context.tolerance
        )
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard case let .setbackCorner(corner) = feature.operation else {
            throw error(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Setback corner evaluator requires a setback corner feature.")
        }
        let quantity = try resolver.evaluate(corner.radius, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length,
              quantity.value.isFinite,
              quantity.value > context.tolerance.distance else {
            throw error(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Setback corner radius must be a positive length above modeling tolerance.")
        }
        let bodyID = try targetBodyID(corner.target.featureID, featureID: feature.id, context: context)
        let vertexID = try targetVertexID(corner.vertex, featureID: feature.id, context: context)
        let bodyScope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
        let replacedSubshapeIDs = bodyScope.subshapeIDs(in: context.subshapes)
        let request = try request(
            featureID: feature.id,
            bodyID: bodyID,
            vertexID: vertexID,
            selectedSubshapeID: corner.vertex.subshapeID,
            radius: quantity.value,
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

    private func targetBodyID(
        _ sourceFeatureID: FeatureID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: sourceFeatureID)
    }

    private func targetVertexID(
        _ reference: StableSubshapeReference,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> VertexID {
        let topology = try subshapeResolver.topologyReference(
            for: reference,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .vertex(vertexID) = topology else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                featureID: featureID,
                subshapeID: reference.subshapeID,
                tolerance: context.tolerance,
                message: "Setback corner selection must resolve to a vertex."
            )
        }
        return vertexID
    }

    private func request(
        featureID: FeatureID,
        bodyID: BodyID,
        vertexID: VertexID,
        selectedSubshapeID: SubshapeID,
        radius: Double,
        context: EvaluationContext
    ) throws -> BRepSewingRequest {
        let model = context.brep
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        let scopedVertexCount = scope.references.reduce(into: 0) { count, reference in
            if case .vertex = reference { count += 1 }
        }
        let scopedEdgeCount = scope.references.reduce(into: 0) { count, reference in
            if case .edge = reference { count += 1 }
        }
        let scopedEdgeIDs = Set(scope.references.compactMap { reference -> EdgeID? in
            if case let .edge(edgeID) = reference { return edgeID }
            return nil
        })
        let scopedVertexIDs = Set(scope.references.compactMap { reference -> VertexID? in
            if case let .vertex(vertexID) = reference { return vertexID }
            return nil
        })
        guard let body = model.bodies[bodyID],
              body.kind == .solid,
              body.shellIDs.count == 1,
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              shell.faceIDs.count == 6,
              scopedVertexCount == 8,
              scopedEdgeCount == 12,
              let corner = model.vertices[vertexID]?.point else {
            throw error(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Current exact setback corner requires one orthogonal hexahedral solid.")
        }
        let incidentEdges = scopedEdgeIDs.compactMap { model.edges[$0] }.filter {
            $0.startVertexID == vertexID || $0.endVertexID == vertexID
        }
        guard incidentEdges.count == 3 else {
            throw error(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Setback corner vertex must have exactly three incident edges.")
        }
        let unorderedEdgeGeometry = try incidentEdges.map { edge -> EdgeGeometry in
            let farVertexID = edge.startVertexID == vertexID ? edge.endVertexID : edge.startVertexID
            guard let farPoint = model.vertices[farVertexID]?.point,
                  case .line = model.geometry.curves[edge.curveID] else {
                throw error(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Setback corner incident edges must be straight.")
            }
            let vector = farPoint - corner
            guard vector.length > radius + context.tolerance.distance else {
                throw error(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Setback corner radius must fit every incident edge.")
            }
            return EdgeGeometry(
                edgeID: edge.id,
                farVertexID: farVertexID,
                farPoint: farPoint,
                direction: try vector.normalized(tolerance: context.tolerance.distance),
                length: vector.length,
                parentSubshapeIDs: subshapeIDs(for: .edge(edge.id), context: context),
                farVertexParentSubshapeIDs: subshapeIDs(for: .vertex(farVertexID), context: context)
            )
        }
        let edgeGeometry = canonicalEdgeGeometry(unorderedEdgeGeometry)
        for first in edgeGeometry.indices {
            for second in edgeGeometry.indices where second > first {
                guard abs(edgeGeometry[first].direction.dot(edgeGeometry[second].direction)) <= context.tolerance.angle else {
                    throw error(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Setback corner incident edges must be mutually perpendicular.")
                }
            }
        }
        let incidentFaceIDs = shell.faceIDs.filter { faceContains(vertexID: vertexID, faceID: $0, model: model) }
        guard incidentFaceIDs.count == 3,
              shell.faceIDs.allSatisfy({ faceID in
                  guard let face = model.faces[faceID] else { return false }
                  if case .plane = model.geometry.surfaces[face.surfaceID] { return face.loops.count == 1 }
                  return false
              }) else {
            throw error(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Setback corner requires six untrimmed planar faces.")
        }
        let center = corner
            + edgeGeometry[0].direction * radius
            + edgeGeometry[1].direction * radius
            + edgeGeometry[2].direction * radius
        let tangent01 = center + edgeGeometry[2].direction * (-radius)
        let tangent02 = center + edgeGeometry[1].direction * (-radius)
        let tangent12 = center + edgeGeometry[0].direction * (-radius)
        let tangentPairs = [
            (start: tangent02, end: tangent01),
            (start: tangent01, end: tangent12),
            (start: tangent12, end: tangent02),
        ]
        var patches: [BRepSewingFacePatch] = []
        for (faceIndex, faceID) in incidentFaceIDs.sorted().enumerated() {
            let polygon = try outerPolygon(faceID: faceID, model: model, featureID: featureID, tolerance: context.tolerance)
            guard let cornerIndex = polygon.firstIndex(where: {
                $0.isApproximatelyEqual(to: corner, tolerance: context.tolerance.distance)
            }) else {
                throw error(.topologyFailure, featureID: featureID, tolerance: context.tolerance, "Setback corner incident face does not contain the selected vertex.")
            }
            let rotated = polygon.indices.map { polygon[(cornerIndex + $0) % polygon.count] }
            guard rotated.count == 4 else {
                throw error(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Setback corner incident faces must be quadrilateral.")
            }
            let next = try (rotated[1] - corner).normalized(tolerance: context.tolerance.distance)
            let previous = try (rotated[rotated.count - 1] - corner).normalized(tolerance: context.tolerance.distance)
            let replacement = corner + (next + previous) * radius
            let nextReplacement = rotated[1] + previous * radius
            let previousReplacement = rotated[rotated.count - 1] + next * radius
            let boundary = [replacement, nextReplacement, rotated[2], previousReplacement]
            patches.append(try planarPatch(
                stableID: "source-face:incident:\(faceIndex)",
                faceID: faceID,
                vertices: boundary,
                selectedEdges: edgeGeometry,
                sourceEdgeIDs: scopedEdgeIDs,
                sourceVertexIDs: scopedVertexIDs,
                model: model,
                context: context
            ))
        }
        var plans: [CylinderPlan] = []
        for index in edgeGeometry.indices {
            let geometry = edgeGeometry[index]
            let otherIndices = edgeGeometry.indices.filter { $0 != index }
            let baseCenter = corner
                + edgeGeometry[otherIndices[0]].direction * radius
                + edgeGeometry[otherIndices[1]].direction * radius
            let surface = Surface3D.cylinder(Cylinder3D(
                origin: baseCenter,
                axis: geometry.direction,
                radius: radius
            ))
            let centralCircle = Curve3D.circle(Circle3D(
                center: center,
                normal: geometry.direction,
                radius: radius
            ))
            let farCenter = baseCenter + geometry.direction * geometry.length
            let farCircle = Curve3D.circle(Circle3D(
                center: farCenter,
                normal: geometry.direction,
                radius: radius
            ))
            let startProjection = try surface.parameterProjection(of: tangentPairs[index].start, tolerance: context.tolerance)
            let endProjection = try surface.parameterProjection(of: tangentPairs[index].end, tolerance: context.tolerance)
            let endU = nearestQuarterTurn(from: startProjection.u, to: endProjection.u)
            guard abs(abs(endU - startProjection.u) - Double.pi / 2.0) <= context.tolerance.angle * 16.0 else {
                throw error(.topologyFailure, featureID: featureID, tolerance: context.tolerance, "Setback cylinder must span one quarter turn.")
            }
            let plan = CylinderPlan(
                geometry: geometry,
                surface: surface,
                centralCircle: centralCircle,
                farCircle: farCircle,
                uStart: startProjection.u,
                uEnd: endU,
                centralStart: tangentPairs[index].start,
                centralEnd: tangentPairs[index].end
            )
            plans.append(plan)
            let capFaceID = try farCapFaceID(
                geometry: geometry,
                incidentFaceIDs: Set(incidentFaceIDs),
                shell: shell,
                model: model,
                featureID: featureID,
                tolerance: context.tolerance
            )
            patches.append(try farCapPatch(
                stableID: "source-face:cap:\(index)",
                faceID: capFaceID,
                plan: plan,
                radius: radius,
                sourceEdgeIDs: scopedEdgeIDs,
                sourceVertexIDs: scopedVertexIDs,
                model: model,
                context: context,
                featureID: featureID
            ))
        }
        for (index, plan) in plans.enumerated() {
            let incidentParents = incidentFaceIDs.filter {
                faceUses(edgeID: plan.geometry.edgeID, faceID: $0, model: model)
            }.flatMap { subshapeIDs(for: .face($0), context: context) }
            patches.append(try cylinderPatch(
                stableID: "setback:cylinder:\(index)",
                plan: plan,
                radius: radius,
                faceParents: incidentParents,
                tolerance: context.tolerance
            ))
        }
        patches.append(try spherePatch(
            center: center,
            radius: radius,
            selectedVertexParent: selectedSubshapeID,
            plans: plans,
            tolerance: context.tolerance
        ))
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(stableID: "setback:shell", patches: patches)],
            bodyParentSubshapeIDs: subshapeIDs(for: .body(bodyID), context: context)
        )
    }

    private func planarPatch(
        stableID: String,
        faceID: FaceID,
        vertices: [Point3D],
        selectedEdges: [EdgeGeometry],
        sourceEdgeIDs: Set<EdgeID>,
        sourceVertexIDs: Set<VertexID>,
        model: BRepModel,
        context: EvaluationContext
    ) throws -> BRepSewingFacePatch {
        guard let face = model.faces[faceID],
              case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("Setback planar face is missing.")
        }
        let surface = Surface3D.plane(plane)
        let edges = try vertices.indices.map { index in
            let start = vertices[index]
            let end = vertices[(index + 1) % vertices.count]
            return try lineEdge(
                stableID: "\(stableID):edge:\(index)",
                start: start,
                end: end,
                surface: surface,
                edgeParents: sourceEdgeParents(
                    start: start,
                    end: end,
                    selectedEdges: selectedEdges,
                    sourceEdgeIDs: sourceEdgeIDs,
                    model: model,
                    context: context
                ),
                startVertexParents: sourceVertexParents(
                    start,
                    sourceVertexIDs: sourceVertexIDs,
                    model: model,
                    context: context
                ),
                endVertexParents: sourceVertexParents(
                    end,
                    sourceVertexIDs: sourceVertexIDs,
                    model: model,
                    context: context
                ),
                tolerance: context.tolerance
            )
        }
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: face.orientation,
            loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
            parentSubshapeIDs: subshapeIDs(for: .face(faceID), context: context)
        )
    }

    private func farCapPatch(
        stableID: String,
        faceID: FaceID,
        plan: CylinderPlan,
        radius: Double,
        sourceEdgeIDs: Set<EdgeID>,
        sourceVertexIDs: Set<VertexID>,
        model: BRepModel,
        context: EvaluationContext,
        featureID: FeatureID
    ) throws -> BRepSewingFacePatch {
        guard let face = model.faces[faceID],
              case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else {
            throw error(.topologyFailure, featureID: featureID, tolerance: context.tolerance, "Setback far cap is not planar.")
        }
        let polygon = try outerPolygon(faceID: faceID, model: model, featureID: featureID, tolerance: context.tolerance)
        guard let cornerIndex = polygon.firstIndex(where: {
            $0.isApproximatelyEqual(to: plan.geometry.farPoint, tolerance: context.tolerance.distance)
        }) else {
            throw error(.topologyFailure, featureID: featureID, tolerance: context.tolerance, "Setback far cap does not contain its edge endpoint.")
        }
        let rotated = polygon.indices.map { polygon[(cornerIndex + $0) % polygon.count] }
        let nextDirection = rotated[1] - plan.geometry.farPoint
        let previousDirection = rotated[rotated.count - 1] - plan.geometry.farPoint
        guard nextDirection.length > radius + context.tolerance.distance,
              previousDirection.length > radius + context.tolerance.distance else {
            throw error(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Setback radius must fit each far cap edge.")
        }
        let tangentNext = plan.geometry.farPoint
            + (try nextDirection.normalized(tolerance: context.tolerance.distance)) * radius
        let tangentPrevious = plan.geometry.farPoint
            + (try previousDirection.normalized(tolerance: context.tolerance.distance)) * radius
        let boundary = [tangentNext] + Array(rotated.dropFirst()) + [tangentPrevious]
        let surface = Surface3D.plane(plane)
        var edges = try (0..<(boundary.count - 1)).map { index in
            try lineEdge(
                stableID: "\(stableID):edge:\(index)",
                start: boundary[index],
                end: boundary[index + 1],
                surface: surface,
                edgeParents: sourceEdgeParents(
                    start: boundary[index],
                    end: boundary[index + 1],
                    selectedEdges: [],
                    sourceEdgeIDs: sourceEdgeIDs,
                    model: model,
                    context: context
                ),
                startVertexParents: sourceVertexParents(
                    boundary[index],
                    sourceVertexIDs: sourceVertexIDs,
                    model: model,
                    context: context
                ),
                endVertexParents: sourceVertexParents(
                    boundary[index + 1],
                    sourceVertexIDs: sourceVertexIDs,
                    model: model,
                    context: context
                ),
                tolerance: context.tolerance
            )
        }
        let startProjection = try plan.farCircle.parameterProjection(of: tangentPrevious, tolerance: context.tolerance)
        let endProjection = try plan.farCircle.parameterProjection(of: tangentNext, tolerance: context.tolerance)
        let endParameter = nearestQuarterTurn(from: startProjection.parameter, to: endProjection.parameter)
        edges.append(try circleEdge(
            stableID: "\(stableID):arc",
            curve: plan.farCircle,
            start: startProjection.parameter,
            end: endParameter,
            pcurve: try harmonicPcurve(
                curve: plan.farCircle,
                surface: surface,
                start: startProjection.parameter,
                end: endParameter,
                tolerance: context.tolerance
            ),
            startVertexParents: plan.geometry.farVertexParentSubshapeIDs,
            endVertexParents: plan.geometry.farVertexParentSubshapeIDs,
            tolerance: context.tolerance
        ))
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: face.orientation,
            loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
            parentSubshapeIDs: subshapeIDs(for: .face(faceID), context: context)
        )
    }

    private func cylinderPatch(
        stableID: String,
        plan: CylinderPlan,
        radius: Double,
        faceParents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        let central = try circleEdge(
            stableID: "\(stableID):central",
            curve: plan.centralCircle,
            start: plan.uStart,
            end: plan.uEnd,
            pcurve: .constantV(v: radius, uStart: plan.uStart, uEnd: plan.uEnd),
            tolerance: tolerance
        )
        let endLine = try cylinderAxialEdge(
            stableID: "\(stableID):end",
            plan: plan,
            u: plan.uEnd,
            start: radius,
            end: plan.geometry.length,
            tolerance: tolerance
        )
        let far = try circleEdge(
            stableID: "\(stableID):far",
            curve: plan.farCircle,
            start: plan.uEnd,
            end: plan.uStart,
            pcurve: .constantV(v: plan.geometry.length, uStart: plan.uEnd, uEnd: plan.uStart),
            tolerance: tolerance
        )
        let startLine = try cylinderAxialEdge(
            stableID: "\(stableID):start",
            plan: plan,
            u: plan.uStart,
            start: plan.geometry.length,
            end: radius,
            tolerance: tolerance
        )
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: plan.surface,
            orientation: .forward,
            loops: [BRepSewingLoop(
                stableID: "\(stableID):outer",
                role: .outer,
                edges: [central, endLine, far, startLine]
            )],
            parentSubshapeIDs: faceParents
        )
    }

    private func spherePatch(
        center: Point3D,
        radius: Double,
        selectedVertexParent: SubshapeID,
        plans: [CylinderPlan],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        let surface = Surface3D.analytic(.sphere(center: center, radius: radius))
        let reversed = try plans.map { plan in
            let basis = try greatCircleBasis(curve: plan.centralCircle, center: center, tolerance: tolerance)
            return try circleEdge(
                stableID: "sphere:\(plan.geometry.edgeID)",
                curve: plan.centralCircle,
                start: plan.uEnd,
                end: plan.uStart,
                pcurve: .sphericalGreatCircle(
                    cosine: basis.cosine,
                    sine: basis.sine,
                    startParameter: plan.uEnd,
                    endParameter: plan.uStart
                ),
                startVertexParents: [selectedVertexParent],
                endVertexParents: [selectedVertexParent],
                tolerance: tolerance
            )
        }
        let ordered = [reversed[0], reversed[2], reversed[1]]
        return BRepSewingFacePatch(
            stableID: "setback:sphere",
            surface: surface,
            orientation: .forward,
            loops: [BRepSewingLoop(stableID: "setback:sphere:outer", role: .outer, edges: ordered)]
        )
    }

    private func cylinderAxialEdge(
        stableID: String,
        plan: CylinderPlan,
        u: Double,
        start: Double,
        end: Double,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let startPoint = try plan.surface.point(u: u, v: start, tolerance: tolerance)
        let endPoint = try plan.surface.point(u: u, v: end, tolerance: tolerance)
        let delta = endPoint - startPoint
        return BRepSewingEdge(
            stableID: stableID,
            curve: .line(Line3D(origin: startPoint, direction: try delta.normalized(tolerance: tolerance.distance))),
            startParameter: 0.0,
            endParameter: delta.length,
            startPoint: startPoint,
            endPoint: endPoint,
            surfaceParameterCurve: .constantU(u: u, vStart: start, vEnd: end),
            parentSubshapeIDs: plan.geometry.parentSubshapeIDs
        )
    }

    private func lineEdge(
        stableID: String,
        start: Point3D,
        end: Point3D,
        surface: Surface3D,
        edgeParents: [SubshapeID],
        startVertexParents: [SubshapeID],
        endVertexParents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let delta = end - start
        let startUV = try surface.parameterProjection(of: start, tolerance: tolerance)
        let endUV = try surface.parameterProjection(of: end, tolerance: tolerance)
        return BRepSewingEdge(
            stableID: stableID,
            curve: .line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance))),
            startParameter: 0.0,
            endParameter: delta.length,
            startPoint: start,
            endPoint: end,
            surfaceParameterCurve: .polyline([
                SurfaceParameter(u: startUV.u, v: startUV.v),
                SurfaceParameter(u: endUV.u, v: endUV.v),
            ]),
            parentSubshapeIDs: edgeParents,
            startVertexParentSubshapeIDs: startVertexParents,
            endVertexParentSubshapeIDs: endVertexParents
        )
    }

    private func circleEdge(
        stableID: String,
        curve: Curve3D,
        start: Double,
        end: Double,
        pcurve: SurfaceParameterCurve,
        startVertexParents: [SubshapeID] = [],
        endVertexParents: [SubshapeID] = [],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: start,
            endParameter: end,
            startPoint: try curve.point(at: start, tolerance: tolerance),
            endPoint: try curve.point(at: end, tolerance: tolerance),
            surfaceParameterCurve: pcurve,
            startVertexParentSubshapeIDs: startVertexParents,
            endVertexParentSubshapeIDs: endVertexParents
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
            throw error(.invalidInput, tolerance: tolerance, "Setback cap trim must be circular.")
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

    private func greatCircleBasis(
        curve: Curve3D,
        center: Point3D,
        tolerance: ModelingTolerance
    ) throws -> (cosine: Vector3D, sine: Vector3D) {
        let cosine = try (curve.point(at: 0.0, tolerance: tolerance) - center).normalized(tolerance: tolerance.distance)
        let sine = try (curve.point(at: Double.pi / 2.0, tolerance: tolerance) - center).normalized(tolerance: tolerance.distance)
        return (cosine, sine)
    }

    private func farCapFaceID(
        geometry: EdgeGeometry,
        incidentFaceIDs: Set<FaceID>,
        shell: Shell,
        model: BRepModel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> FaceID {
        let candidates = shell.faceIDs.filter {
            incidentFaceIDs.contains($0) == false
                && faceContains(vertexID: geometry.farVertexID, faceID: $0, model: model)
        }
        guard candidates.count == 1, let faceID = candidates.first else {
            throw error(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "Each setback edge must terminate at one planar cap face.")
        }
        return faceID
    }

    private func outerPolygon(
        faceID: FaceID,
        model: BRepModel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        guard let face = model.faces[faceID],
              face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer else {
            throw error(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "Setback corner requires one outer loop per face.")
        }
        return try loop.coedges.map { coedge in
            guard let edge = model.edges[coedge.edgeID] else { throw TopologyError.missingReference("Missing setback source edge.") }
            let vertexID = coedge.orientation == .forward ? edge.startVertexID : edge.endVertexID
            guard let vertex = model.vertices[vertexID] else { throw TopologyError.missingReference("Missing setback source vertex.") }
            return vertex.point
        }
    }

    private func faceContains(vertexID: VertexID, faceID: FaceID, model: BRepModel) -> Bool {
        guard let face = model.faces[faceID] else { return false }
        return face.loops.contains { loopID in
            model.loops[loopID]?.coedges.contains { coedge in
                guard let edge = model.edges[coedge.edgeID] else { return false }
                return edge.startVertexID == vertexID || edge.endVertexID == vertexID
            } == true
        }
    }

    private func faceUses(edgeID: EdgeID, faceID: FaceID, model: BRepModel) -> Bool {
        guard let face = model.faces[faceID] else { return false }
        return face.loops.contains { model.loops[$0]?.coedges.contains { $0.edgeID == edgeID } == true }
    }

    private func sourceEdgeParents(
        start: Point3D,
        end: Point3D,
        selectedEdges: [EdgeGeometry],
        sourceEdgeIDs: Set<EdgeID>,
        model: BRepModel,
        context: EvaluationContext
    ) -> [SubshapeID] {
        for edgeID in sourceEdgeIDs.sorted() {
            guard let edge = model.edges[edgeID] else { continue }
            guard let first = model.vertices[edge.startVertexID]?.point,
                  let second = model.vertices[edge.endVertexID]?.point,
                  point(start, on: first, second, tolerance: context.tolerance),
                  point(end, on: first, second, tolerance: context.tolerance) else { continue }
            let parents = subshapeIDs(for: .edge(edge.id), context: context)
            if parents.isEmpty == false { return parents }
        }
        let candidate = end - start
        return selectedEdges.first { geometry in
            let scale = max(candidate.length, Double.leastNonzeroMagnitude)
            return candidate.cross(geometry.direction).length <= context.tolerance.angle * scale
        }?.parentSubshapeIDs ?? []
    }

    private func sourceVertexParents(
        _ point: Point3D,
        sourceVertexIDs: Set<VertexID>,
        model: BRepModel,
        context: EvaluationContext
    ) -> [SubshapeID] {
        for vertexID in sourceVertexIDs.sorted() {
            guard let vertex = model.vertices[vertexID],
                  vertex.point.isApproximatelyEqual(to: point, tolerance: context.tolerance.distance) else {
                continue
            }
            return subshapeIDs(for: .vertex(vertex.id), context: context)
        }
        return []
    }

    private func canonicalEdgeGeometry(_ geometry: [EdgeGeometry]) -> [EdgeGeometry] {
        var ordered = geometry.sorted { first, second in
            if first.direction.x != second.direction.x {
                return first.direction.x < second.direction.x
            }
            if first.direction.y != second.direction.y {
                return first.direction.y < second.direction.y
            }
            return first.direction.z < second.direction.z
        }
        if ordered.count == 3,
           ordered[0].direction.dot(ordered[1].direction.cross(ordered[2].direction)) < 0.0 {
            ordered.swapAt(1, 2)
        }
        return ordered
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

    private func nearestQuarterTurn(from start: Double, to end: Double) -> Double {
        var delta = end - start
        while delta > Double.pi { delta -= 2.0 * Double.pi }
        while delta < -Double.pi { delta += 2.0 * Double.pi }
        return start + delta
    }

    private func error(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }

    private struct EdgeGeometry {
        let edgeID: EdgeID
        let farVertexID: VertexID
        let farPoint: Point3D
        let direction: Vector3D
        let length: Double
        let parentSubshapeIDs: [SubshapeID]
        let farVertexParentSubshapeIDs: [SubshapeID]
    }

    private struct CylinderPlan {
        let geometry: EdgeGeometry
        let surface: Surface3D
        let centralCircle: Curve3D
        let farCircle: Curve3D
        let uStart: Double
        let uEnd: Double
        let centralStart: Point3D
        let centralEnd: Point3D
    }
}
