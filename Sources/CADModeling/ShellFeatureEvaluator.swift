import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct ShellFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving
    private let sewer: any BRepSewing

    public init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
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
        guard case let .shell(shell) = feature.operation else {
            throw kernelError(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Shell evaluator requires a shell feature.")
        }
        guard shell.removedFaces.count == 1 else {
            throw kernelError(.unsupportedCapability, featureID: feature.id, tolerance: context.tolerance, "Current exact shell supports one removed face per feature.")
        }
        let quantity = try resolver.evaluate(shell.thickness, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length,
              quantity.value.isFinite,
              quantity.value > context.tolerance.distance else {
            throw kernelError(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Shell thickness must be a positive length above modeling tolerance.")
        }
        let bodyID = try targetBodyID(shell.target.featureID, featureID: feature.id, context: context)
        let bodyScope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
        let removedFaceID = try targetFaceID(
            shell.removedFaces[0],
            in: bodyScope,
            featureID: feature.id,
            context: context
        )
        let replacedSubshapeIDs = bodyScope.subshapeIDs(in: context.subshapes)
        let request = try request(
            featureID: feature.id,
            bodyID: bodyID,
            removedFaceID: removedFaceID,
            removedSubshapeID: shell.removedFaces[0].subshapeID,
            bodyScope: bodyScope,
            thickness: quantity.value,
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

    private func targetFaceID(
        _ reference: StableSubshapeReference,
        in bodyScope: BodyTopologyScope,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> FaceID {
        let topology = try subshapeResolver.topologyReference(
            for: reference,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .face(faceID) = topology else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                featureID: featureID,
                subshapeID: reference.subshapeID,
                tolerance: context.tolerance,
                message: "Shell removal selection must resolve to a face."
            )
        }
        guard bodyScope.references.contains(.face(faceID)) else {
            throw kernelError(
                .missingReference,
                featureID: featureID,
                subshapeID: reference.subshapeID,
                tolerance: context.tolerance,
                "Shell removal face must belong to the target body."
            )
        }
        return faceID
    }

    private func request(
        featureID: FeatureID,
        bodyID: BodyID,
        removedFaceID: FaceID,
        removedSubshapeID: SubshapeID,
        bodyScope: BodyTopologyScope,
        thickness: Double,
        context: EvaluationContext
    ) throws -> BRepSewingRequest {
        let model = context.brep
        let scopedVertexIDs = Set(bodyScope.references.compactMap { reference -> VertexID? in
            if case let .vertex(vertexID) = reference { return vertexID }
            return nil
        })
        let scopedEdgeIDs = Set(bodyScope.references.compactMap { reference -> EdgeID? in
            if case let .edge(edgeID) = reference { return edgeID }
            return nil
        })
        let scopedVertexCount = bodyScope.references.reduce(into: 0) { count, reference in
            if case .vertex = reference { count += 1 }
        }
        let scopedEdgeCount = bodyScope.references.reduce(into: 0) { count, reference in
            if case .edge = reference { count += 1 }
        }
        guard let body = model.bodies[bodyID],
              body.kind == .solid,
              body.shellIDs.count == 1,
              let shellID = body.shellIDs.first,
              let sourceShell = model.shells[shellID],
              sourceShell.faceIDs.count == 6,
              scopedVertexCount == 8,
              scopedEdgeCount == 12,
              let removedFace = model.faces[removedFaceID],
              case let .plane(removedPlane) = model.geometry.surfaces[removedFace.surfaceID] else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Current exact shell requires one orthogonal hexahedral solid.")
        }
        let opening = try outerPolygon(
            faceID: removedFaceID,
            model: model,
            featureID: featureID,
            tolerance: context.tolerance
        )
        guard opening.count == 4 else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Shell opening face must be quadrilateral.")
        }
        let origin = opening[0]
        let uVector = opening[1] - origin
        let vVector = opening[3] - origin
        let width = uVector.length
        let height = vVector.length
        let u = try uVector.normalized(tolerance: context.tolerance.distance)
        let v = try vVector.normalized(tolerance: context.tolerance.distance)
        let removedOutward = removedFace.orientation == .forward ? removedPlane.normal : -removedPlane.normal
        let w = -removedOutward
        guard abs(u.dot(v)) <= context.tolerance.angle,
              abs(u.dot(w)) <= context.tolerance.angle,
              abs(v.dot(w)) <= context.tolerance.angle,
              opening[2].isApproximatelyEqual(
                  to: origin + u * width + v * height,
                  tolerance: context.tolerance.distance
              ) else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Shell opening must be an orthogonal rectangle.")
        }
        let depth = try scopedVertexIDs.sorted().map { vertexID -> Double in
            guard let vertex = model.vertices[vertexID] else {
                throw kernelError(
                    .missingReference,
                    featureID: featureID,
                    tolerance: context.tolerance,
                    "Shell target body is missing a scoped vertex."
                )
            }
            let parameter = (vertex.point - origin).dot(w)
            guard parameter >= -context.tolerance.distance else {
                throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Shell body must lie inward from the removed face.")
            }
            return parameter
        }.max() ?? 0.0
        guard depth > 2.0 * thickness + context.tolerance.distance,
              width > 2.0 * thickness + context.tolerance.distance,
              height > 2.0 * thickness + context.tolerance.distance else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Shell thickness must fit every body dimension.")
        }
        let sourceFaces = try sourceFaceMap(
            shell: sourceShell,
            removedFaceID: removedFaceID,
            u: u,
            v: v,
            w: w,
            model: model,
            featureID: featureID,
            tolerance: context.tolerance
        )
        func point(_ uValue: Double, _ vValue: Double, _ wValue: Double) -> Point3D {
            origin + u * uValue + v * vValue + w * wValue
        }
        let q00 = point(0.0, 0.0, 0.0)
        let q10 = point(width, 0.0, 0.0)
        let q11 = point(width, height, 0.0)
        let q01 = point(0.0, height, 0.0)
        let b00 = point(0.0, 0.0, depth)
        let b10 = point(width, 0.0, depth)
        let b11 = point(width, height, depth)
        let b01 = point(0.0, height, depth)
        let i00 = point(thickness, thickness, 0.0)
        let i10 = point(width - thickness, thickness, 0.0)
        let i11 = point(width - thickness, height - thickness, 0.0)
        let i01 = point(thickness, height - thickness, 0.0)
        let innerDepth = depth - thickness
        let ib00 = point(thickness, thickness, innerDepth)
        let ib10 = point(width - thickness, thickness, innerDepth)
        let ib11 = point(width - thickness, height - thickness, innerDepth)
        let ib01 = point(thickness, height - thickness, innerDepth)
        let removedParents = [removedSubshapeID]
        var definitions: [PatchDefinition] = [
            .init("outer:u0", [q00, q01, b01, b00], -u, parents(sourceFaces.u0, context)),
            .init("outer:u1", [q10, b10, b11, q11], u, parents(sourceFaces.u1, context)),
            .init("outer:v0", [q00, b00, b10, q10], -v, parents(sourceFaces.v0, context)),
            .init("outer:v1", [q01, q11, b11, b01], v, parents(sourceFaces.v1, context)),
            .init("outer:bottom", [b00, b01, b11, b10], w, parents(sourceFaces.bottom, context)),
            .init("inner:u0", [i00, ib00, ib01, i01], u, parents(sourceFaces.u0, context)),
            .init("inner:u1", [i10, i11, ib11, ib10], -u, parents(sourceFaces.u1, context)),
            .init("inner:v0", [i00, i10, ib10, ib00], v, parents(sourceFaces.v0, context)),
            .init("inner:v1", [i01, ib01, ib11, i11], -v, parents(sourceFaces.v1, context)),
            .init("inner:bottom", [ib00, ib10, ib11, ib01], -w, parents(sourceFaces.bottom, context)),
            .init("rim:v0", [q00, q10, i10, i00], -w, removedParents + parents(sourceFaces.v0, context)),
            .init("rim:u1", [q10, q11, i11, i10], -w, removedParents + parents(sourceFaces.u1, context)),
            .init("rim:v1", [q11, q01, i01, i11], -w, removedParents + parents(sourceFaces.v1, context)),
            .init("rim:u0", [q01, q00, i00, i01], -w, removedParents + parents(sourceFaces.u0, context)),
        ]
        definitions = definitions.map { definition in
            var vertices = definition.vertices
            if polygonNormal(vertices).dot(definition.outward) < 0.0 {
                vertices.reverse()
            }
            return PatchDefinition(definition.stableID, vertices, definition.outward, definition.parents)
        }
        let patches = try definitions.map {
            try patch(
                $0,
                sourceEdgeIDs: scopedEdgeIDs,
                sourceVertexIDs: scopedVertexIDs,
                model: model,
                context: context
            )
        }
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(stableID: "shell:0", patches: patches)],
            bodyParentSubshapeIDs: subshapeIDs(for: .body(bodyID), context: context)
        )
    }

    private func sourceFaceMap(
        shell: Shell,
        removedFaceID: FaceID,
        u: Vector3D,
        v: Vector3D,
        w: Vector3D,
        model: BRepModel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> SourceFaces {
        func face(matching normal: Vector3D) -> FaceID? {
            shell.faceIDs.first { faceID in
                guard faceID != removedFaceID,
                      let face = model.faces[faceID],
                      case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else { return false }
                let outward = face.orientation == .forward ? plane.normal : -plane.normal
                return outward.dot(normal) >= 1.0 - tolerance.angle
            }
        }
        guard let u0 = face(matching: -u),
              let u1 = face(matching: u),
              let v0 = face(matching: -v),
              let v1 = face(matching: v),
              let bottom = face(matching: w) else {
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "Shell source faces do not form an orthogonal hexahedron.")
        }
        return SourceFaces(u0: u0, u1: u1, v0: v0, v1: v1, bottom: bottom)
    }

    private func patch(
        _ definition: PatchDefinition,
        sourceEdgeIDs: Set<EdgeID>,
        sourceVertexIDs: Set<VertexID>,
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
                parentSubshapeIDs: sourceEdgeParents(
                    start: start,
                    end: end,
                    sourceEdgeIDs: sourceEdgeIDs,
                    model: model,
                    context: context
                ),
                startVertexParentSubshapeIDs: sourceVertexParents(
                    start,
                    sourceVertexIDs: sourceVertexIDs,
                    model: model,
                    context: context
                ),
                endVertexParentSubshapeIDs: sourceVertexParents(
                    end,
                    sourceVertexIDs: sourceVertexIDs,
                    model: model,
                    context: context
                )
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
            throw kernelError(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "Shell faces require one outer loop.")
        }
        return try loop.coedges.map { coedge in
            guard let edge = model.edges[coedge.edgeID] else { throw TopologyError.missingReference("Missing shell source edge.") }
            let vertexID = coedge.orientation == .forward ? edge.startVertexID : edge.endVertexID
            guard let vertex = model.vertices[vertexID] else { throw TopologyError.missingReference("Missing shell source vertex.") }
            return vertex.point
        }
    }

    private func parents(_ faceID: FaceID, _ context: EvaluationContext) -> [SubshapeID] {
        subshapeIDs(for: .face(faceID), context: context)
    }

    private func sourceEdgeParents(
        start: Point3D,
        end: Point3D,
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
            let result = subshapeIDs(for: .edge(edge.id), context: context)
            if result.isEmpty == false { return result }
        }
        return []
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

    private struct SourceFaces {
        let u0: FaceID
        let u1: FaceID
        let v0: FaceID
        let v1: FaceID
        let bottom: FaceID
    }

    private struct PatchDefinition {
        let stableID: String
        let vertices: [Point3D]
        let outward: Vector3D
        let parents: [SubshapeID]

        init(_ stableID: String, _ vertices: [Point3D], _ outward: Vector3D, _ parents: [SubshapeID]) {
            self.stableID = stableID
            self.vertices = vertices
            self.outward = outward
            self.parents = Array(Set(parents)).sorted()
        }
    }
}
