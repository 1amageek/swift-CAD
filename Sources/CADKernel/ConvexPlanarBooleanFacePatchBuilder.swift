import CADCore
import CADTopology
import CADGeometry
import CADIR
import CADModeling

struct ConvexPlanarBooleanFacePatchBuilder {
    let tolerance: ModelingTolerance

    func request(
        operation: BooleanOperation,
        target: ConvexPlanarSolidOperand,
        tool: ConvexPlanarSolidOperand,
        featureID: FeatureID
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingRequest {
        try execution.consumeWork(1)
        try tolerance.validate()
        let targetPolygons = try polygons(from: target, using: &execution)
        let toolPolygons = try polygons(from: tool, using: &execution)
        let evaluated = try evaluate(
            operation: operation,
            target: targetPolygons,
            tool: toolPolygons
        , using: &execution)
        let result = try conformed(evaluated, using: &execution)
        guard result.count >= 4 else {
            throw FeatureEvaluationError.emptyResult(
                "Convex planar Boolean produced no volumetric boundary."
            )
        }
        let components = try connectedComponents(result, using: &execution)
        let shells = try components.enumerated().map { componentIndex, component in
            guard component.count >= 4 else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Planar Boolean produced a boundary component with fewer than four faces."
                )
            }
            let faces = try PlanarBooleanFragmentMerger(tolerance: tolerance).merged(component, using: &execution)
            let patches = try faces.enumerated().map { faceIndex, face in
                try patch(
                    stableID: "planar-csg:component:\(componentIndex):face:\(faceIndex)",
                    face: face
                , using: &execution)
            }
            return BRepSewingShell(
                stableID: "planar-csg:shell:\(componentIndex)",
                patches: patches
            )
        }
        let request = BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: shells
        )
        try request.validate(tolerance: tolerance, using: &execution)
        return request
    }

    private func polygons(
        from operand: ConvexPlanarSolidOperand
    , using execution: inout OriginalQueryExecution) throws -> [PlanarBooleanPolygon] {
        try execution.consumeWork(1)
        return try operand.faces.map { face in
            // Each polygon winds counterclockwise about its outward normal, read off its own
            // winding: a body extruded against its section's normal winds every loop the other
            // way, which its faces' orientation flags alone do not tell.
            var winding = Vector3D.zero
            for (start, end) in zip(face.vertices, face.vertices.dropFirst() + face.vertices.prefix(1)) {
            try execution.consumeWork(1)
                winding = winding + (start - face.vertices[0]).cross(end - face.vertices[0])
            }
            let vertices = winding.dot(face.outwardNormal) < 0 ? Array(face.vertices.reversed()) : face.vertices
            return try PlanarBooleanPolygon(
                vertices: vertices,
                surface: face.surface,
                surfaceOrientation: face.orientation,
                plane: PlanarBooleanPlane(
                    origin: face.planeOrigin,
                    normal: face.outwardNormal,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            , using: &execution)
        }
    }

    private func evaluate(
        operation: BooleanOperation,
        target: [PlanarBooleanPolygon],
        tool: [PlanarBooleanPolygon]
    , using execution: inout OriginalQueryExecution) throws -> [PlanarBooleanPolygon] {
        try execution.consumeWork(1)
        let first = try PlanarBooleanBSPNode(polygons: target, tolerance: tolerance, using: &execution)
        let second = try PlanarBooleanBSPNode(polygons: tool, tolerance: tolerance, using: &execution)
        switch operation {
        case .union:
            try first.clip(to: second, using: &execution)
            try second.clip(to: first, using: &execution)
            try second.inverted(using: &execution)
            try second.clip(to: first, using: &execution)
            try second.inverted(using: &execution)
            let secondPolygons = try second.allPolygons(using: &execution)
            try first.build(secondPolygons, using: &execution)
        case .difference:
            try first.inverted(using: &execution)
            try first.clip(to: second, using: &execution)
            try second.clip(to: first, using: &execution)
            try second.inverted(using: &execution)
            try second.clip(to: first, using: &execution)
            try second.inverted(using: &execution)
            let secondPolygons = try second.allPolygons(using: &execution)
            try first.build(secondPolygons, using: &execution)
            try first.inverted(using: &execution)
        case .intersect:
            try first.inverted(using: &execution)
            try second.clip(to: first, using: &execution)
            try second.inverted(using: &execution)
            try first.clip(to: second, using: &execution)
            try second.clip(to: first, using: &execution)
            let secondPolygons = try second.allPolygons(using: &execution)
            try first.build(secondPolygons, using: &execution)
            try first.inverted(using: &execution)
        case .slice, .region:
            throw KernelError(
                phase: .evaluation,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Planar BSP materialization supports union, difference, and intersection."
            )
        }
        return try first.allPolygons(using: &execution)
    }

    private func conformed(
        _ polygons: [PlanarBooleanPolygon]
    , using execution: inout OriginalQueryExecution) throws -> [PlanarBooleanPolygon] {
        try execution.consumeWork(1)
        let candidates = polygons.flatMap(\.vertices)
        return try polygons.map { polygon in
            var vertices: [Point3D] = []
            for index in polygon.vertices.indices {
            try execution.consumeWork(1)
                let start = polygon.vertices[index]
                let end = polygon.vertices[(index + 1) % polygon.vertices.count]
                let direction = end - start
                let squaredLength = direction.dot(direction)
                let length = direction.length
                guard squaredLength > tolerance.distance * tolerance.distance else {
                    continue
                }
                let interior = candidates.compactMap { point -> (parameter: Double, point: Point3D)? in
                    let parameter = (point - start).dot(direction) / squaredLength
                    guard parameter > tolerance.distance / length,
                          parameter < 1.0 - tolerance.distance / length else {
                        return nil
                    }
                    let projected = start + direction * parameter
                    guard projected.isApproximatelyEqual(to: point, tolerance: tolerance.distance) else {
                        return nil
                    }
                    return (parameter, projected)
                }.sorted { $0.parameter < $1.parameter }
                try append(start, to: &vertices, using: &execution)
                for candidate in interior {
            try execution.consumeWork(1)
                    try append(candidate.point, to: &vertices, using: &execution)
                }
            }
            return try PlanarBooleanPolygon(
                vertices: vertices,
                surface: polygon.surface,
                surfaceOrientation: polygon.surfaceOrientation,
                plane: polygon.plane,
                preserveCollinearVertices: true,
                tolerance: tolerance
            , using: &execution)
        }
    }

    private func append(
        _ point: Point3D,
        to points: inout [Point3D],
        using execution: inout OriginalQueryExecution
    ) throws {
        if points.last?.isApproximatelyEqual(to: point, tolerance: tolerance.distance) != true {
            try OriginalParameterQueryStorage.append(point, to: &points, using: &execution)
        }
    }

    private func connectedComponents(
        _ polygons: [PlanarBooleanPolygon]
    , using execution: inout OriginalQueryExecution) throws -> [[PlanarBooleanPolygon]] {
        try execution.consumeWork(1)
        var remaining = Set(polygons.indices)
        var components: [[PlanarBooleanPolygon]] = []
        while let seed = remaining.min() {
            try execution.consumeWork(1)
            remaining.remove(seed)
            var indices = [seed]
            var frontier = [seed]
            while let current = frontier.popLast() {
            try execution.consumeWork(1)
                let neighbors = try remaining.filter { candidate in
                    try sharesBoundaryEdge(polygons[current], polygons[candidate], using: &execution)
                }.sorted()
                for neighbor in neighbors {
            try execution.consumeWork(1)
                    remaining.remove(neighbor)
                    indices.append(neighbor)
                    frontier.append(neighbor)
                }
            }
            components.append(indices.sorted().map { polygons[$0] })
        }
        return components
    }

    private func sharesBoundaryEdge(
        _ first: PlanarBooleanPolygon,
        _ second: PlanarBooleanPolygon
    , using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        for firstIndex in first.vertices.indices {
            try execution.consumeWork(1)
            let firstStart = first.vertices[firstIndex]
            let firstEnd = first.vertices[(firstIndex + 1) % first.vertices.count]
            for secondIndex in second.vertices.indices {
            try execution.consumeWork(1)
                let secondStart = second.vertices[secondIndex]
                let secondEnd = second.vertices[(secondIndex + 1) % second.vertices.count]
                if firstStart.isApproximatelyEqual(to: secondEnd, tolerance: tolerance.distance),
                   firstEnd.isApproximatelyEqual(to: secondStart, tolerance: tolerance.distance) {
                    return true
                }
            }
        }
        return false
    }

    private func patch(
        stableID: String,
        face: PlanarBooleanMergedFace
    , using execution: inout OriginalQueryExecution) throws -> BRepSewingFacePatch {
        try execution.consumeWork(1)
        guard let origin = face.loops.first?.first else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Planar Boolean output face has no origin vertex."
            )
        }
        let surface = Surface3D.plane(Plane3D(
            origin: origin,
            normal: face.normal
        ))
        let loops = try face.loops.enumerated().map { loopIndex, loopVertices in
            let loopID = loopIndex == 0 ? "\(stableID):outer" : "\(stableID):inner:\(loopIndex)"
            let edges = try loopVertices.indices.map { index in
                let start = loopVertices[index]
                let end = loopVertices[(index + 1) % loopVertices.count]
                let delta = end - start
                guard delta.length > tolerance.distance else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "Planar Boolean generated a collapsed boundary edge."
                    )
                }
                let startUV = try surface.parameterProjection(of: start, tolerance: tolerance, using: &execution)
                let endUV = try surface.parameterProjection(of: end, tolerance: tolerance, using: &execution)
                return BRepSewingEdge(
                    stableID: loopIndex == 0 ? "\(stableID):edge:\(index)" : "\(loopID):edge:\(index)",
                    curve: .line(Line3D(
                        origin: start,
                        direction: try delta.normalized(tolerance: tolerance.distance)
                    )),
                    startParameter: 0.0,
                    endParameter: delta.length,
                    startPoint: start,
                    endPoint: end,
                    surfaceParameterCurve: .polyline([
                        SurfaceParameter(u: startUV.u, v: startUV.v),
                        SurfaceParameter(u: endUV.u, v: endUV.v),
                    ])
                )
            }
            return BRepSewingLoop(stableID: loopID, role: loopIndex == 0 ? .outer : .inner, edges: edges)
        }
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: .forward,
            loops: loops
        )
    }
}
