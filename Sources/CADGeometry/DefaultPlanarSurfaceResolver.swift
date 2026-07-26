import CADCore

struct DefaultPlanarSurfaceResolver: PlanarSurfaceResolving {
    func canonicalPlane(
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
        }
    }

    func exactPlane(
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
        var candidateNormal: Vector3D?
        for point in points.dropFirst() {
            let candidateDirection = point - origin
            let cross = firstDirection.cross(candidateDirection)
            let minimumArea = tolerance.distance * max(
                firstDirection.length,
                candidateDirection.length
            )
            if cross.length > minimumArea {
                candidateNormal = cross
                break
            }
        }
        guard let normal = candidateNormal else { return nil }
        let unitNormal = try normal.normalized(
            tolerance: tolerance.distance
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
