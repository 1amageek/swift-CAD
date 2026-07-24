import CADCore
import CADGeometry
import CADIR
import CADTopology
import Foundation

public extension DocumentCaches {
    func validateFreshness(
        for document: CADDocument,
        tolerance: ModelingTolerance,
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
            try curveSignature(curve),
            trimSignature(edge.trim),
            try canonicalEncodingSignature(orientedEdge.surfaceParameterCurve)
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
    case let .analytic(surface):
        return analyticSurfaceSignature(surface)
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

private func curveSignature(_ curve: Curve3D) throws -> String {
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
    case let .analytic(curve):
        return analyticCurveSignature(curve)
    case let .bSpline(curve):
        return [
            "bSpline",
            "\(curve.degree)",
            curve.knots.map(doubleSignature).joined(separator: ";"),
            curve.controlPoints.map(pointSignature).joined(separator: ";"),
            curve.weights.map(doubleSignature).joined(separator: ";")
        ].joined(separator: ",")
    case let .implicit(curve):
        let cellSignatures = curve.cells.map { cell in
            let intervals = cell.parameterBox.intervals.flatMap { interval in
                [doubleSignature(interval.lower), doubleSignature(interval.upper)]
            }
            let anchors = [
                cell.lowerAnchor,
                cell.midpointAnchor,
                cell.upperAnchor,
            ].flatMap { anchor in anchor.values.map(doubleSignature) }
            return ([String(cell.freeParameter.rawValue), cell.direction.rawValue] + intervals + anchors)
                .joined(separator: ";")
        }
        return [
            "implicit",
            surfaceSignature(.bSpline(curve.firstSurface)),
            surfaceSignature(.bSpline(curve.secondSurface)),
            curve.isClosed ? "closed" : "open",
            cellSignatures.joined(separator: "|")
        ].joined(separator: ",")
    case let .surfaceLift(curve):
        return [
            "surfaceLift",
            surfaceSignature(curve.surface),
            try canonicalEncodingSignature(curve.parameterCurve)
        ].joined(separator: ",")
    case let .certifiedIntersection(curve):
        return [
            "certifiedIntersection",
            try canonicalEncodingSignature(curve)
        ].joined(separator: ",")
    }
}

private func analyticSurfaceSignature(_ surface: AnalyticSurface3D) -> String {
    switch surface {
    case let .plane(origin, normal):
        return ["analyticPlane", pointSignature(origin), vectorSignature(normal)].joined(separator: ",")
    case let .cylinder(origin, axis, radius):
        return [
            "analyticCylinder", pointSignature(origin), vectorSignature(axis), doubleSignature(radius)
        ].joined(separator: ",")
    case let .cone(apex, axis, halfAngle):
        return [
            "analyticCone", pointSignature(apex), vectorSignature(axis), doubleSignature(halfAngle)
        ].joined(separator: ",")
    case let .sphere(center, radius):
        return ["analyticSphere", pointSignature(center), doubleSignature(radius)].joined(separator: ",")
    case let .torus(center, axis, majorRadius, minorRadius):
        return [
            "analyticTorus",
            pointSignature(center),
            vectorSignature(axis),
            doubleSignature(majorRadius),
            doubleSignature(minorRadius)
        ].joined(separator: ",")
    }
}

private func analyticCurveSignature(_ curve: AnalyticCurve3D) -> String {
    switch curve {
    case let .line(origin, direction):
        return ["analyticLine", pointSignature(origin), vectorSignature(direction)].joined(separator: ",")
    case let .circle(center, normal, radius):
        return [
            "analyticCircle", pointSignature(center), vectorSignature(normal), doubleSignature(radius)
        ].joined(separator: ",")
    case let .arc(center, normal, radius, startAngle, endAngle):
        return [
            "analyticArc",
            pointSignature(center),
            vectorSignature(normal),
            doubleSignature(radius),
            doubleSignature(startAngle),
            doubleSignature(endAngle)
        ].joined(separator: ",")
    case let .ellipse(center, normal, majorAxis, majorRadius, minorRadius):
        return [
            "analyticEllipse",
            pointSignature(center),
            vectorSignature(normal),
            vectorSignature(majorAxis),
            doubleSignature(majorRadius),
            doubleSignature(minorRadius)
        ].joined(separator: ",")
    case let .hyperbola(curve):
        return [
            "analyticHyperbola",
            pointSignature(curve.center),
            vectorSignature(curve.normal),
            vectorSignature(curve.transverseAxis),
            doubleSignature(curve.transverseRadius),
            doubleSignature(curve.conjugateRadius)
        ].joined(separator: ",")
    case let .parabola(curve):
        return [
            "analyticParabola",
            pointSignature(curve.vertex),
            vectorSignature(curve.normal),
            vectorSignature(curve.axis),
            doubleSignature(curve.focalLength)
        ].joined(separator: ",")
    case let .planeTorus(curve):
        return [
            "planeTorus",
            surfaceSignature(curve.planeSurface),
            surfaceSignature(curve.torusSurface),
            curve.componentKind.rawValue,
            doubleSignature(curve.lowerMinorAngle),
            doubleSignature(curve.upperMinorAngle),
            doubleSignature(curve.certificationTolerance.distance),
            doubleSignature(curve.certificationTolerance.angle),
            doubleSignature(curve.certificationTolerance.relative),
            doubleSignature(curve.maximumResidualUpperBound)
        ].joined(separator: ",")
    }
}

private func canonicalEncodingSignature<Value: Encodable>(
    _ value: Value
) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value).base64EncodedString()
}

private func canonicalEncodingSignature<Value: Encodable>(
    _ value: Value?
) throws -> String {
    guard let value else { return "nil" }
    return try canonicalEncodingSignature(value)
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
