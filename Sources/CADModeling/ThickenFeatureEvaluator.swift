import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct ThickenFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let sewer: any BRepSewing

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        sewer: any BRepSewing = DefaultBRepSewer()
    ) {
        self.resolver = resolver
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
        guard case let .thicken(thicken) = feature.operation else {
            throw kernelError(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Thicken evaluator requires a thicken feature.")
        }
        let quantity = try resolver.evaluate(thicken.thickness, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length,
              quantity.value.isFinite,
              quantity.value > context.tolerance.distance else {
            throw kernelError(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Thicken thickness must be a positive length above modeling tolerance.")
        }
        let bodyID = try targetBodyID(thicken.target.featureID, featureID: feature.id, context: context)
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: bodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        let request = try request(
            featureID: feature.id,
            bodyID: bodyID,
            thickness: quantity.value,
            side: thicken.side,
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

    private func request(
        featureID: FeatureID,
        bodyID: BodyID,
        thickness: Double,
        side: ThickenSide,
        context: EvaluationContext
    ) throws -> BRepSewingRequest {
        let model = context.brep
        guard let body = model.bodies[bodyID],
              body.kind == .sheet,
              body.shellIDs.count == 1,
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              shell.faceIDs.count == 1,
              let faceID = shell.faceIDs.first,
              let face = model.faces[faceID],
              face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer,
              loop.coedges.count >= 3,
              case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Current exact thicken requires one untrimmed planar sheet face.")
        }
        let normal = face.orientation == .forward ? plane.normal : -plane.normal
        var boundary = try loop.coedges.map { coedge -> BoundaryVertex in
            guard let edge = model.edges[coedge.edgeID],
                  case .line = model.geometry.curves[edge.curveID] else {
                throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Current exact thicken requires straight sheet boundaries.")
            }
            let vertexID = coedge.orientation == .forward ? edge.startVertexID : edge.endVertexID
            guard let vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference("Thicken sheet vertex is missing.")
            }
            return BoundaryVertex(
                point: vertex.point,
                sourceEdgeID: edge.id,
                sourceVertexID: vertexID
            )
        }
        if polygonNormal(boundary.map(\.point)).dot(normal) < 0.0 {
            boundary.reverse()
            boundary = boundary.indices.map { index in
                let sourceIndex = (index + 1) % boundary.count
                return BoundaryVertex(
                    point: boundary[index].point,
                    sourceEdgeID: boundary[sourceIndex].sourceEdgeID,
                    sourceVertexID: boundary[index].sourceVertexID
                )
            }
        }
        let offsets: (lower: Double, upper: Double)
        switch side {
        case .positive:
            offsets = (0.0, thickness)
        case .negative:
            offsets = (-thickness, 0.0)
        case .symmetric:
            offsets = (-0.5 * thickness, 0.5 * thickness)
        }
        let lower = boundary.map { $0.point + normal * offsets.lower }
        let upper = boundary.map { $0.point + normal * offsets.upper }
        let faceParents = subshapeIDs(for: .face(faceID), context: context)
        var definitions: [PatchDefinition] = [
            PatchDefinition(stableID: "thicken:lower", vertices: lower, outward: -normal, parents: faceParents),
            PatchDefinition(stableID: "thicken:upper", vertices: upper, outward: normal, parents: faceParents),
        ]
        for index in boundary.indices {
            let next = (index + 1) % boundary.count
            let direction = try (boundary[next].point - boundary[index].point).normalized(
                tolerance: context.tolerance.distance
            )
            definitions.append(PatchDefinition(
                stableID: "thicken:side:\(index)",
                vertices: [lower[index], lower[next], upper[next], upper[index]],
                outward: direction.cross(normal),
                parents: []
            ))
        }
        let patches = try definitions.map { definition in
            var vertices = definition.vertices
            if polygonNormal(vertices).dot(definition.outward) < 0.0 {
                vertices.reverse()
            }
            return try patch(
                PatchDefinition(
                    stableID: definition.stableID,
                    vertices: vertices,
                    outward: definition.outward,
                    parents: definition.parents
                ),
                boundary: boundary,
                lower: lower,
                upper: upper,
                model: model,
                context: context
            )
        }
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(stableID: "thicken:shell", patches: patches)],
            bodyParentSubshapeIDs: subshapeIDs(for: .body(bodyID), context: context)
        )
    }

    private func patch(
        _ definition: PatchDefinition,
        boundary: [BoundaryVertex],
        lower: [Point3D],
        upper: [Point3D],
        model: BRepModel,
        context: EvaluationContext
    ) throws -> BRepSewingFacePatch {
        let surface = Surface3D.plane(Plane3D(origin: definition.vertices[0], normal: definition.outward))
        let edges = try definition.vertices.indices.map { index in
            let start = definition.vertices[index]
            let end = definition.vertices[(index + 1) % definition.vertices.count]
            let delta = end - start
            let startUV = try surface.parameterProjection(of: start, tolerance: context.tolerance)
            let endUV = try surface.parameterProjection(of: end, tolerance: context.tolerance)
            let sourceEdgeParents = perimeterEdgeParents(
                start: start,
                end: end,
                boundary: boundary,
                lower: lower,
                upper: upper,
                context: context
            )
            let startVertexParents = derivedVertexParents(
                start,
                boundary: boundary,
                lower: lower,
                upper: upper,
                context: context
            )
            let endVertexParents = derivedVertexParents(
                end,
                boundary: boundary,
                lower: lower,
                upper: upper,
                context: context
            )
            return BRepSewingEdge(
                stableID: "\(definition.stableID):edge:\(index)",
                curve: .line(Line3D(origin: start, direction: try delta.normalized(tolerance: context.tolerance.distance))),
                startParameter: 0.0,
                endParameter: delta.length,
                startPoint: start,
                endPoint: end,
                surfaceParameterCurve: .polyline([
                    SurfaceParameter(u: startUV.u, v: startUV.v),
                    SurfaceParameter(u: endUV.u, v: endUV.v),
                ]),
                parentSubshapeIDs: sourceEdgeParents,
                startVertexParentSubshapeIDs: startVertexParents,
                endVertexParentSubshapeIDs: endVertexParents
            )
        }
        return BRepSewingFacePatch(
            stableID: definition.stableID,
            surface: surface,
            orientation: .forward,
            loops: [BRepSewingLoop(stableID: "\(definition.stableID):outer", role: .outer, edges: edges)],
            parentSubshapeIDs: definition.parents
        )
    }

    private func perimeterEdgeParents(
        start: Point3D,
        end: Point3D,
        boundary: [BoundaryVertex],
        lower: [Point3D],
        upper: [Point3D],
        context: EvaluationContext
    ) -> [SubshapeID] {
        for index in boundary.indices {
            let next = (index + 1) % boundary.count
            let matchesLower = segment(start, end, matches: lower[index], lower[next], tolerance: context.tolerance.distance)
            let matchesUpper = segment(start, end, matches: upper[index], upper[next], tolerance: context.tolerance.distance)
            if matchesLower || matchesUpper {
                return subshapeIDs(for: .edge(boundary[index].sourceEdgeID), context: context)
            }
        }
        return []
    }

    private func derivedVertexParents(
        _ point: Point3D,
        boundary: [BoundaryVertex],
        lower: [Point3D],
        upper: [Point3D],
        context: EvaluationContext
    ) -> [SubshapeID] {
        for index in boundary.indices where point.isApproximatelyEqual(
            to: lower[index],
            tolerance: context.tolerance.distance
        ) || point.isApproximatelyEqual(
            to: upper[index],
            tolerance: context.tolerance.distance
        ) {
            return subshapeIDs(for: .vertex(boundary[index].sourceVertexID), context: context)
        }
        return []
    }

    private func segment(
        _ firstStart: Point3D,
        _ firstEnd: Point3D,
        matches secondStart: Point3D,
        _ secondEnd: Point3D,
        tolerance: Double
    ) -> Bool {
        firstStart.isApproximatelyEqual(to: secondStart, tolerance: tolerance)
            && firstEnd.isApproximatelyEqual(to: secondEnd, tolerance: tolerance)
            || firstStart.isApproximatelyEqual(to: secondEnd, tolerance: tolerance)
            && firstEnd.isApproximatelyEqual(to: secondStart, tolerance: tolerance)
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

    private func subshapeIDs(for reference: TopologyReference, context: EvaluationContext) -> [SubshapeID] {
        context.subshapeIDs(for: reference)
    }

    private func kernelError(
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

    private struct BoundaryVertex {
        let point: Point3D
        let sourceEdgeID: EdgeID
        let sourceVertexID: VertexID
    }

    private struct PatchDefinition {
        let stableID: String
        let vertices: [Point3D]
        let outward: Vector3D
        let parents: [SubshapeID]
    }
}
