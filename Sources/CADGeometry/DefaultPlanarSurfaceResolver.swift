import CADCore

package struct DefaultPlanarSurfaceResolver: PlanarSurfaceResolving {
    package init() {}

    package func canonicalPlane(
        for surface: Surface3D
    ) -> ResolvedPlaneGeometry? {
        switch surface {
        case let .plane(plane):
            return ResolvedPlaneGeometry(
                origin: plane.origin,
                normal: plane.normal
            )
        case let .analytic(.plane(origin, normal)):
            return ResolvedPlaneGeometry(
                origin: origin,
                normal: normal
            )
        case .cylinder, .analytic, .bSpline:
            return nil
        case let .procedural(.offset(offset)):
            guard let sourcePlane = canonicalPlane(for: offset.source) else {
                return nil
            }
            return ResolvedPlaneGeometry(
                origin: sourcePlane.origin + sourcePlane.normal * offset.distance,
                normal: sourcePlane.normal
            )
        case .procedural(.ruled):
            return nil
        }
    }

    package func exactPlane(
        for surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ResolvedPlaneGeometry? {
        if let canonical = canonicalPlane(for: surface) {
            return canonical
        }
        if case let .bSpline(surface) = surface {
            return try plane(
                forControlPoints: surface.controlPoints.flatMap { $0 },
                tolerance: tolerance
            )
        }
        if case let .procedural(.offset(offset)) = surface,
           let sourcePlane = try exactPlane(
               for: offset.source,
               tolerance: tolerance
           ) {
            return ResolvedPlaneGeometry(
                origin: sourcePlane.origin + sourcePlane.normal * offset.distance,
                normal: sourcePlane.normal
            )
        }
        return nil
    }

    private func plane(
        forControlPoints points: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> ResolvedPlaneGeometry? {
        guard let origin = points.first else { return nil }
        guard let first = points.dropFirst().first(where: {
            ($0 - origin).length > tolerance.distance
        }) else {
            return nil
        }
        let firstDirection = first - origin
        var candidateNormal: (vector: Vector3D, minimumArea: Double)?
        for point in points.dropFirst() {
            let candidateDirection = point - origin
            let cross = firstDirection.cross(candidateDirection)
            let minimumArea = tolerance.distance * max(
                firstDirection.length,
                candidateDirection.length
            )
            if cross.length > minimumArea {
                candidateNormal = (cross, minimumArea)
                break
            }
        }
        guard let candidateNormal else { return nil }
        let unitNormal = try candidateNormal.vector.normalized(
            tolerance: candidateNormal.minimumArea
        )
        let coordinateScale = points.reduce(1.0) { scale, point in
            max(
                scale,
                max(abs(point.x), max(abs(point.y), abs(point.z)))
            )
        }
        let arithmeticEnvelope =
            coordinateScale * Double.ulpOfOne * 4_096.0
        guard points.allSatisfy({
            abs(($0 - origin).dot(unitNormal)) <= arithmeticEnvelope
        }) else {
            return nil
        }
        return ResolvedPlaneGeometry(
            origin: origin,
            normal: unitNormal
        )
    }
}
