import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct ChamferFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
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
        guard case let .chamfer(chamfer) = feature.operation else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "Chamfer evaluator requires a chamfer feature."
            )
        }
        guard chamfer.edges.count == 1 else {
            throw unsupported(
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "Current exact chamfer supports one selected edge per feature."
            )
        }
        let distance = try resolvedDistance(chamfer.distance, context: context, featureID: feature.id)
        let bodyID = try targetBodyID(chamfer.target.featureID, context: context, featureID: feature.id)
        guard let body = context.brep.bodies[bodyID],
              body.kind == .solid,
              body.shellIDs.count == 1 else {
            throw unsupported(
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "Current exact chamfer requires one single-shell solid body."
            )
        }
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: bodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        let selectedReference = chamfer.edges[0]
        let edgeID = try targetEdgeID(selectedReference, context: context, featureID: feature.id)
        let request = try sewingRequest(
            featureID: feature.id,
            bodyID: bodyID,
            selectedEdgeID: edgeID,
            selectedSubshapeID: selectedReference.subshapeID,
            distance: distance,
            context: context
        )
        let sewn = try sewer.sew(request, tolerance: context.tolerance)
        let model = try BRepBodyModelReplacer().replacing(
            bodyID: bodyID,
            with: sewn.bodyID,
            from: sewn.brep,
            in: context.brep
        )
        try model.validate(level: .volumetric, tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: sewn.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: sewn.lineage
        )
    }

    private func resolvedDistance(
        _ expression: CADExpression,
        context: EvaluationContext,
        featureID: FeatureID
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length,
              quantity.value.isFinite,
              quantity.value > context.tolerance.distance else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                featureID: featureID,
                residual: quantity.value,
                tolerance: context.tolerance,
                message: "Chamfer distance must be a positive length above modeling tolerance."
            )
        }
        return quantity.value
    }

    private func targetBodyID(
        _ targetFeatureID: FeatureID,
        context: EvaluationContext,
        featureID: FeatureID
    ) throws -> BodyID {
        try context.bodyID(generatedBy: targetFeatureID)
    }

    private func targetEdgeID(
        _ reference: StableSubshapeReference,
        context: EvaluationContext,
        featureID: FeatureID
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
                message: "Chamfer selection must resolve to an edge."
            )
        }
        return edgeID
    }

    private func sewingRequest(
        featureID: FeatureID,
        bodyID: BodyID,
        selectedEdgeID: EdgeID,
        selectedSubshapeID: SubshapeID,
        distance: Double,
        context: EvaluationContext
    ) throws -> BRepSewingRequest {
        let model = context.brep
        guard let body = model.bodies[bodyID],
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              let selectedEdge = model.edges[selectedEdgeID],
              let firstVertex = model.vertices[selectedEdge.startVertexID],
              let secondVertex = model.vertices[selectedEdge.endVertexID] else {
            throw missingReference(featureID: featureID, tolerance: context.tolerance)
        }
        let incidentFaceIDs = try shell.faceIDs.filter { faceID in
            try faceUses(edgeID: selectedEdgeID, faceID: faceID, model: model)
        }
        guard incidentFaceIDs.count == 2 else {
            throw unsupported(
                featureID: featureID,
                tolerance: context.tolerance,
                message: "Chamfer edge must have exactly two incident faces."
            )
        }
        let firstPlane = try orientedPlane(
            faceID: incidentFaceIDs[0],
            model: model,
            featureID: featureID,
            tolerance: context.tolerance
        )
        let secondPlane = try orientedPlane(
            faceID: incidentFaceIDs[1],
            model: model,
            featureID: featureID,
            tolerance: context.tolerance
        )
        guard abs(firstPlane.outwardNormal.dot(secondPlane.outwardNormal)) <= context.tolerance.angle else {
            throw unsupported(
                featureID: featureID,
                tolerance: context.tolerance,
                message: "Chamfer incident faces must be perpendicular planes."
            )
        }
        let edgeDirection = try (secondVertex.point - firstVertex.point).normalized(
            tolerance: context.tolerance.distance
        )
        guard abs(edgeDirection.dot(firstPlane.outwardNormal)) <= context.tolerance.angle,
              abs(edgeDirection.dot(secondPlane.outwardNormal)) <= context.tolerance.angle else {
            throw unsupported(
                featureID: featureID,
                tolerance: context.tolerance,
                message: "Chamfer edge must lie on both incident planes."
            )
        }
        let firstInward = -firstPlane.outwardNormal
        let secondInward = -secondPlane.outwardNormal
        let halfspaceNormal = firstInward + secondInward
        let incidentFaceParents = incidentFaceIDs.flatMap {
            subshapeIDs(for: .face($0), context: context)
        }
        var patches: [BRepSewingFacePatch] = []
        for (faceIndex, faceID) in shell.faceIDs.enumerated() {
            let plane = try orientedPlane(
                faceID: faceID,
                model: model,
                featureID: featureID,
                tolerance: context.tolerance
            )
            let polygon = try outerPolygon(
                faceID: faceID,
                model: model,
                featureID: featureID,
                tolerance: context.tolerance
            )
            let clipped = simplified(
                clip(
                    polygon,
                    origin: firstVertex.point,
                    normal: halfspaceNormal,
                    offset: distance,
                    tolerance: context.tolerance
                ),
                tolerance: context.tolerance
            )
            guard clipped.count >= 3 else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    featureID: featureID,
                    tolerance: context.tolerance,
                    message: "Chamfer distance removes an entire source face."
                )
            }
            patches.append(try facePatch(
                stableID: "source-face:\(faceIndex)",
                surface: .plane(plane.plane),
                orientation: plane.orientation,
                vertices: clipped,
                parentSubshapeIDs: subshapeIDs(for: .face(faceID), context: context),
                edgeParentSubshapeIDs: clipped.indices.map { index in
                    sourceEdgeParents(
                        start: clipped[index],
                        end: clipped[(index + 1) % clipped.count],
                        selectedEdgeID: selectedEdgeID,
                        selectedSubshapeID: selectedSubshapeID,
                        model: model,
                        context: context
                    )
                },
                tolerance: context.tolerance
            ))
        }
        var chamferVertices = [
            firstVertex.point + firstInward * distance,
            secondVertex.point + firstInward * distance,
            secondVertex.point + secondInward * distance,
            firstVertex.point + secondInward * distance,
        ]
        let chamferOutward = try (-halfspaceNormal).normalized(tolerance: context.tolerance.distance)
        if polygonNormal(chamferVertices).dot(chamferOutward) < 0.0 {
            chamferVertices.reverse()
        }
        patches.append(try facePatch(
            stableID: "chamfer-face",
            surface: .plane(Plane3D(origin: chamferVertices[0], normal: chamferOutward)),
            orientation: .forward,
            vertices: chamferVertices,
            parentSubshapeIDs: incidentFaceParents,
            edgeParentSubshapeIDs: [
                [selectedSubshapeID],
                [],
                [selectedSubshapeID],
                [],
            ],
            tolerance: context.tolerance
        ))
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(stableID: "shell:0", patches: patches)],
            bodyParentSubshapeIDs: subshapeIDs(for: .body(bodyID), context: context)
        )
    }

    private func orientedPlane(
        faceID: FaceID,
        model: BRepModel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> (plane: Plane3D, orientation: Orientation, outwardNormal: Vector3D) {
        guard let face = model.faces[faceID],
              case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else {
            throw unsupported(
                featureID: featureID,
                tolerance: tolerance,
                message: "Current exact chamfer requires planar source faces."
            )
        }
        let outward = face.orientation == .forward ? plane.normal : -plane.normal
        return (plane, face.orientation, outward)
    }

    private func faceUses(edgeID: EdgeID, faceID: FaceID, model: BRepModel) throws -> Bool {
        guard let face = model.faces[faceID] else { throw TopologyError.missingReference("Missing face.") }
        return try face.loops.contains { loopID in
            guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing loop.") }
            return loop.edges.contains { $0.edgeID == edgeID }
        }
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
            throw unsupported(
                featureID: featureID,
                tolerance: tolerance,
                message: "Current exact chamfer requires one untrimmed outer loop per face."
            )
        }
        return try loop.edges.map { coedge in
            guard let edge = model.edges[coedge.edgeID] else {
                throw TopologyError.missingReference("Missing chamfer source edge.")
            }
            let vertexID = coedge.orientation == .forward ? edge.startVertexID : edge.endVertexID
            guard let vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference("Missing chamfer source vertex.")
            }
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
        guard polygon.isEmpty == false else { return [] }
        var result: [Point3D] = []
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let startValue = (start - origin).dot(normal) - offset
            let endValue = (end - origin).dot(normal) - offset
            let startInside = startValue >= -tolerance.distance
            let endInside = endValue >= -tolerance.distance
            if startInside {
                result.append(start)
            }
            if startInside != endInside {
                let denominator = startValue - endValue
                if abs(denominator) > Double.ulpOfOne {
                    let parameter = startValue / denominator
                    result.append(start + (end - start) * parameter)
                }
            }
        }
        return result
    }

    private func simplified(
        _ polygon: [Point3D],
        tolerance: ModelingTolerance
    ) -> [Point3D] {
        var result: [Point3D] = []
        for point in polygon where result.last?.isApproximatelyEqual(
            to: point,
            tolerance: tolerance.distance
        ) != true {
            result.append(point)
        }
        if result.count > 1,
           result[0].isApproximatelyEqual(to: result[result.count - 1], tolerance: tolerance.distance) {
            result.removeLast()
        }
        var changed = true
        while changed && result.count > 3 {
            changed = false
            for index in result.indices {
                let previous = result[(index + result.count - 1) % result.count]
                let current = result[index]
                let next = result[(index + 1) % result.count]
                let first = current - previous
                let second = next - current
                if first.cross(second).length <= tolerance.distance * max(first.length, second.length) {
                    result.remove(at: index)
                    changed = true
                    break
                }
            }
        }
        return result
    }

    private func facePatch(
        stableID: String,
        surface: Surface3D,
        orientation: Orientation,
        vertices: [Point3D],
        parentSubshapeIDs: [SubshapeID],
        edgeParentSubshapeIDs: [[SubshapeID]],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        guard edgeParentSubshapeIDs.count == vertices.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Chamfer face patch requires one lineage entry per boundary edge."
            )
        }
        let edges = try vertices.indices.map { index in
            let start = vertices[index]
            let end = vertices[(index + 1) % vertices.count]
            let delta = end - start
            let length = delta.length
            let startUV = try surface.parameterProjection(of: start, tolerance: tolerance)
            let endUV = try surface.parameterProjection(of: end, tolerance: tolerance)
            return BRepSewingEdge(
                stableID: "\(stableID):edge:\(index)",
                curve: .line(Line3D(
                    origin: start,
                    direction: try delta.normalized(tolerance: tolerance.distance)
                )),
                startParameter: 0.0,
                endParameter: length,
                startPoint: start,
                endPoint: end,
                surfaceParameterCurve: .polyline([
                    SurfaceParameter(u: startUV.u, v: startUV.v),
                    SurfaceParameter(u: endUV.u, v: endUV.v)
                ]),
                parentSubshapeIDs: edgeParentSubshapeIDs[index]
            )
        }
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: orientation,
            loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
            parentSubshapeIDs: parentSubshapeIDs
        )
    }

    private func sourceEdgeParents(
        start: Point3D,
        end: Point3D,
        selectedEdgeID: EdgeID,
        selectedSubshapeID: SubshapeID,
        model: BRepModel,
        context: EvaluationContext
    ) -> [SubshapeID] {
        for edge in model.edges.values {
            guard let first = model.vertices[edge.startVertexID]?.point,
                  let second = model.vertices[edge.endVertexID]?.point,
                  point(start, liesOnSegmentFrom: first, to: second, tolerance: context.tolerance),
                  point(end, liesOnSegmentFrom: first, to: second, tolerance: context.tolerance) else {
                continue
            }
            let parents = subshapeIDs(for: .edge(edge.id), context: context)
            if parents.isEmpty == false {
                return parents
            }
        }
        guard let selected = model.edges[selectedEdgeID],
              let first = model.vertices[selected.startVertexID]?.point,
              let second = model.vertices[selected.endVertexID]?.point else {
            return []
        }
        let selectedDirection = second - first
        let candidateDirection = end - start
        let scale = max(selectedDirection.length * candidateDirection.length, Double.leastNonzeroMagnitude)
        if selectedDirection.cross(candidateDirection).length <= context.tolerance.angle * scale {
            return [selectedSubshapeID]
        }
        return []
    }

    private func point(
        _ point: Point3D,
        liesOnSegmentFrom start: Point3D,
        to end: Point3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        let segment = end - start
        let length = segment.length
        guard length > tolerance.distance else { return false }
        let offset = point - start
        guard segment.cross(offset).length <= tolerance.distance * length else { return false }
        let parameter = offset.dot(segment) / (length * length)
        return parameter >= -tolerance.distance / length
            && parameter <= 1.0 + tolerance.distance / length
    }

    private func polygonNormal(_ vertices: [Point3D]) -> Vector3D {
        var normal = Vector3D.zero
        for index in vertices.indices {
            let current = vertices[index]
            let next = vertices[(index + 1) % vertices.count]
            normal = normal + Vector3D(
                x: (current.y - next.y) * (current.z + next.z),
                y: (current.z - next.z) * (current.x + next.x),
                z: (current.x - next.x) * (current.y + next.y)
            )
        }
        return normal
    }

    private func subshapeIDs(
        for reference: TopologyReference,
        context: EvaluationContext
    ) -> [SubshapeID] {
        context.subshapeIDs(for: reference)
    }

    private func missingReference(
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: .missingReference,
            featureID: featureID,
            tolerance: tolerance,
            message: "Chamfer topology reference is missing."
        )
    }

    private func unsupported(
        featureID: FeatureID,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: .unsupportedCapability,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }
}
