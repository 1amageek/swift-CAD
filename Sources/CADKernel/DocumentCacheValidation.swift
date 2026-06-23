import CADCore
import CADIR

public extension DocumentCaches {
    func validateFreshness(
        for document: CADDocument,
        tolerance: ModelingTolerance = .standard,
        tessellationOptions: TessellationOptions = .standard,
        kernelVersion: SchemaVersion = .current
    ) throws {
        try validateMetadataFreshness(
            for: document,
            tolerance: tolerance,
            tessellationOptions: tessellationOptions,
            kernelVersion: kernelVersion
        )

        let expectedEvaluation = try DocumentEvaluator(
            tolerance: tolerance,
            tessellationOptions: tessellationOptions
        ).evaluateWithoutCacheValidation(document)

        guard let brep else {
            throw CacheValidationError.missingBRepCache
        }
        guard !meshes.isEmpty else {
            throw CacheValidationError.staleBRepCache("Mesh caches are missing for the evaluated source document.")
        }
        guard try bRepContentSignature(brep.model, tolerance: tolerance)
            == bRepContentSignature(expectedEvaluation.brep, tolerance: tolerance) else {
            throw CacheValidationError.staleBRepCache(
                "B-rep cache content does not match evaluation of the source document."
            )
        }

        let cachedMeshesFromBRep = try MeshTessellator(tolerance: tolerance).tessellate(
            model: brep.model,
            options: tessellationOptions
        )
        let cachedBodyIDs = Set(meshes.keys)
        let cachedBRepBodyIDs = Set(cachedMeshesFromBRep.keys)
        if let missingBodyID = cachedBRepBodyIDs.subtracting(cachedBodyIDs)
            .sorted(by: { $0.description < $1.description })
            .first {
            throw CacheValidationError.staleMeshCache(
                bodyID: missingBodyID,
                reason: "Mesh cache is missing a body generated from the B-rep cache."
            )
        }
        if let extraBodyID = cachedBodyIDs.subtracting(cachedBRepBodyIDs)
            .sorted(by: { $0.description < $1.description })
            .first {
            throw CacheValidationError.staleMeshCache(
                bodyID: extraBodyID,
                reason: "Mesh cache contains a body not generated from the B-rep cache."
            )
        }

        for bodyID in cachedBRepBodyIDs {
            guard let cachedMesh = meshes[bodyID]?.mesh,
                  let expectedMesh = cachedMeshesFromBRep[bodyID],
                  cachedMesh == expectedMesh else {
                throw CacheValidationError.staleMeshCache(
                    bodyID: bodyID,
                    reason: "Mesh cache content does not match tessellation of the B-rep cache."
                )
            }
        }
        guard meshMultiset(meshes.values.map(\.mesh)) == meshMultiset(Array(expectedEvaluation.meshes.values)) else {
            throw CacheValidationError.staleBRepCache(
                "Cached geometry content does not match evaluation of the source document."
            )
        }
    }
}

private func meshMultiset(_ meshes: [Mesh]) -> [Mesh: Int] {
    var counts: [Mesh: Int] = [:]
    for mesh in meshes {
        counts[mesh, default: 0] += 1
    }
    return counts
}

private func bRepContentSignature(_ model: BRepModel, tolerance: ModelingTolerance) throws -> [String] {
    try model.validate(tolerance: tolerance)
    return try model.bodies.values.map { body in
        let shellSignatures = try body.shellIDs.map { shellID -> String in
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing shell \(shellID).")
            }
            return try shellSignature(shell, in: model)
        }.sorted()
        return [
            "body",
            body.kind.rawValue,
            optionalStringSignature(body.name),
            optionalStringSignature(body.material?.description),
            shellSignatures.joined(separator: "|")
        ].joined(separator: ":")
    }.sorted()
}

private func shellSignature(_ shell: Shell, in model: BRepModel) throws -> String {
    let faceSignatures = try shell.faceIDs.map { faceID -> String in
        guard let face = model.faces[faceID] else {
            throw TopologyError.missingReference("Missing face \(faceID).")
        }
        return try faceSignature(face, in: model)
    }.sorted()
    return [
        "shell",
        shell.orientation.rawValue,
        faceSignatures.joined(separator: "|")
    ].joined(separator: ":")
}

private func faceSignature(_ face: Face, in model: BRepModel) throws -> String {
    guard let surface = model.geometry.surfaces[face.surfaceID] else {
        throw TopologyError.missingSurface(face.surfaceID)
    }
    let loopSignatures = try face.loops.map { loopID -> String in
        guard let loop = model.loops[loopID] else {
            throw TopologyError.missingReference("Missing loop \(loopID).")
        }
        return try loopSignature(loop, in: model)
    }.sorted()
    return [
        "face",
        face.orientation.rawValue,
        surfaceSignature(surface),
        loopSignatures.joined(separator: "|")
    ].joined(separator: ":")
}

private func loopSignature(_ loop: Loop, in model: BRepModel) throws -> String {
    let edgeSignatures = try loop.edges.map { orientedEdge -> String in
        guard let edge = model.edges[orientedEdge.edgeID],
              let curve = model.geometry.curves[edge.curveID],
              let start = model.vertices[edge.startVertexID],
              let end = model.vertices[edge.endVertexID] else {
            throw TopologyError.missingReference("Missing loop edge geometry.")
        }
        return [
            orientedEdge.orientation.rawValue,
            pointSignature(start.point),
            pointSignature(end.point),
            curveSignature(curve),
            trimSignature(edge.trim)
        ].joined(separator: ",")
    }
    return [
        "loop",
        loop.role.rawValue,
        edgeSignatures.joined(separator: "|")
    ].joined(separator: ":")
}

private func surfaceSignature(_ surface: Surface3D) -> String {
    switch surface {
    case let .plane(plane):
        return [
            "plane",
            pointSignature(plane.origin),
            vectorSignature(plane.normal)
        ].joined(separator: ",")
    case let .cylinder(cylinder):
        return [
            "cylinder",
            pointSignature(cylinder.origin),
            vectorSignature(cylinder.axis),
            doubleSignature(cylinder.radius)
        ].joined(separator: ",")
    case let .bSpline(surface):
        return [
            "bSpline",
            "\(surface.uDegree)",
            "\(surface.vDegree)",
            surface.uKnots.map(doubleSignature).joined(separator: ";"),
            surface.vKnots.map(doubleSignature).joined(separator: ";"),
            surface.controlPoints
                .map { row in row.map(pointSignature).joined(separator: ";") }
                .joined(separator: "|"),
            surface.weights
                .map { row in row.map(doubleSignature).joined(separator: ";") }
                .joined(separator: "|")
        ].joined(separator: ",")
    }
}

private func curveSignature(_ curve: Curve3D) -> String {
    switch curve {
    case let .line(line):
        return [
            "line",
            pointSignature(line.origin),
            vectorSignature(line.direction)
        ].joined(separator: ",")
    case let .circle(circle):
        return [
            "circle",
            pointSignature(circle.center),
            vectorSignature(circle.normal),
            doubleSignature(circle.radius)
        ].joined(separator: ",")
    case let .bSpline(curve):
        return [
            "bSpline",
            "\(curve.degree)",
            curve.knots.map(doubleSignature).joined(separator: ";"),
            curve.controlPoints.map(pointSignature).joined(separator: ";"),
            curve.weights.map(doubleSignature).joined(separator: ";")
        ].joined(separator: ",")
    }
}

private func trimSignature(_ trim: CurveTrim?) -> String {
    guard let trim else {
        return "nil"
    }
    return [
        doubleSignature(trim.startParameter),
        doubleSignature(trim.endParameter)
    ].joined(separator: ",")
}

private func pointSignature(_ point: Point3D) -> String {
    [
        doubleSignature(point.x),
        doubleSignature(point.y),
        doubleSignature(point.z)
    ].joined(separator: ",")
}

private func vectorSignature(_ vector: Vector3D) -> String {
    [
        doubleSignature(vector.x),
        doubleSignature(vector.y),
        doubleSignature(vector.z)
    ].joined(separator: ",")
}

private func doubleSignature(_ value: Double) -> String {
    String(value)
}

private func optionalStringSignature(_ value: String?) -> String {
    value ?? "nil"
}
