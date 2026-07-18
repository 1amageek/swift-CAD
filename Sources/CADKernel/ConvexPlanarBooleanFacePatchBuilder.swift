import CADCore
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
    ) throws -> BRepSewingRequest {
        try tolerance.validate()
        let targetPolygons = try polygons(from: target)
        let toolPolygons = try polygons(from: tool)
        let evaluated = try evaluate(
            operation: operation,
            target: targetPolygons,
            tool: toolPolygons
        )
        let result = try conformed(evaluated)
        guard result.count >= 4 else {
            throw FeatureEvaluationError.emptyResult(
                "Convex planar Boolean produced no volumetric boundary."
            )
        }
        let components = connectedComponents(result)
        let shells = try components.enumerated().map { componentIndex, component in
            guard component.count >= 4 else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Planar Boolean produced a boundary component with fewer than four faces."
                )
            }
            let patches = try component.enumerated().map { faceIndex, polygon in
                try patch(
                    stableID: "planar-csg:component:\(componentIndex):face:\(faceIndex)",
                    polygon: polygon
                )
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
        try request.validate(tolerance: tolerance)
        return request
    }

    private func polygons(
        from operand: ConvexPlanarSolidOperand
    ) throws -> [PlanarBooleanPolygon] {
        try operand.faces.map { face in
            let vertices = face.orientation == .reversed
                ? Array(face.vertices.reversed())
                : face.vertices
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
            )
        }
    }

    private func evaluate(
        operation: BooleanOperation,
        target: [PlanarBooleanPolygon],
        tool: [PlanarBooleanPolygon]
    ) throws -> [PlanarBooleanPolygon] {
        let first = try PlanarBooleanBSPNode(polygons: target, tolerance: tolerance)
        let second = try PlanarBooleanBSPNode(polygons: tool, tolerance: tolerance)
        switch operation {
        case .union:
            try first.clip(to: second)
            try second.clip(to: first)
            try second.inverted()
            try second.clip(to: first)
            try second.inverted()
            try first.build(second.allPolygons())
        case .difference:
            try first.inverted()
            try first.clip(to: second)
            try second.clip(to: first)
            try second.inverted()
            try second.clip(to: first)
            try second.inverted()
            try first.build(second.allPolygons())
            try first.inverted()
        case .intersect:
            try first.inverted()
            try second.clip(to: first)
            try second.inverted()
            try first.clip(to: second)
            try second.clip(to: first)
            try first.build(second.allPolygons())
            try first.inverted()
        case .slice:
            throw KernelError(
                phase: .evaluation,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Planar BSP materialization supports union, difference, and intersection."
            )
        }
        return first.allPolygons()
    }

    private func conformed(
        _ polygons: [PlanarBooleanPolygon]
    ) throws -> [PlanarBooleanPolygon] {
        let candidates = polygons.flatMap(\.vertices)
        return try polygons.map { polygon in
            var vertices: [Point3D] = []
            for index in polygon.vertices.indices {
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
                append(start, to: &vertices)
                for candidate in interior {
                    append(candidate.point, to: &vertices)
                }
            }
            return try PlanarBooleanPolygon(
                vertices: vertices,
                surface: polygon.surface,
                surfaceOrientation: polygon.surfaceOrientation,
                plane: polygon.plane,
                preserveCollinearVertices: true,
                tolerance: tolerance
            )
        }
    }

    private func append(
        _ point: Point3D,
        to points: inout [Point3D]
    ) {
        if points.last?.isApproximatelyEqual(to: point, tolerance: tolerance.distance) != true {
            points.append(point)
        }
    }

    private func connectedComponents(
        _ polygons: [PlanarBooleanPolygon]
    ) -> [[PlanarBooleanPolygon]] {
        var remaining = Set(polygons.indices)
        var components: [[PlanarBooleanPolygon]] = []
        while let seed = remaining.min() {
            remaining.remove(seed)
            var indices = [seed]
            var frontier = [seed]
            while let current = frontier.popLast() {
                let neighbors = remaining.filter { candidate in
                    sharesBoundaryEdge(polygons[current], polygons[candidate])
                }.sorted()
                for neighbor in neighbors {
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
    ) -> Bool {
        for firstIndex in first.vertices.indices {
            let firstStart = first.vertices[firstIndex]
            let firstEnd = first.vertices[(firstIndex + 1) % first.vertices.count]
            for secondIndex in second.vertices.indices {
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
        polygon: PlanarBooleanPolygon
    ) throws -> BRepSewingFacePatch {
        let loopVertices = polygon.vertices
        guard let origin = loopVertices.first else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Planar Boolean output face has no origin vertex."
            )
        }
        let surface = Surface3D.plane(Plane3D(
            origin: origin,
            normal: polygon.plane.normal
        ))
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
            let startUV = try surface.parameterProjection(of: start, tolerance: tolerance)
            let endUV = try surface.parameterProjection(of: end, tolerance: tolerance)
            return BRepSewingEdge(
                stableID: "\(stableID):edge:\(index)",
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
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: .forward,
            loops: [BRepSewingLoop(
                stableID: "\(stableID):outer",
                role: .outer,
                edges: edges
            )]
        )
    }
}
