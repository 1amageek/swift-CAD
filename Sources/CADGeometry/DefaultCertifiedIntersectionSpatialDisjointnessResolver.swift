import CADCore

struct DefaultCertifiedIntersectionSpatialDisjointnessResolver:
    CertifiedIntersectionSpatialDisjointnessResolving
{
    func areDisjoint(
        curve: CertifiedIntersectionCurve3D,
        target: CanonicalAnalyticSurface,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard let targetBounds = try targetBounds(target) else {
            return false
        }
        let curveBounds = try curve.boundingBox(tolerance: tolerance)
        return curveBounds.intersects(
            targetBounds,
            tolerance: tolerance.distance
        ) == false
    }

    private func targetBounds(
        _ target: CanonicalAnalyticSurface
    ) throws -> BoundingBox3D? {
        switch target {
        case let .sphere(sphere):
            return try isotropicBounds(
                center: sphere.center,
                extent: sphere.radius
            )
        case let .torus(torus):
            let extent = torus.majorRadius + torus.minorRadius
            guard extent.isFinite else {
                return nil
            }
            return try isotropicBounds(
                center: torus.center,
                extent: extent.nextUp
            )
        case .plane, .cylinder, .cone, .unsupported:
            return nil
        }
    }

    private func isotropicBounds(
        center: Point3D,
        extent: Double
    ) throws -> BoundingBox3D? {
        guard extent.isFinite, extent >= 0.0 else {
            return nil
        }
        let minimum = Point3D(
            x: (center.x - extent).nextDown,
            y: (center.y - extent).nextDown,
            z: (center.z - extent).nextDown
        )
        let maximum = Point3D(
            x: (center.x + extent).nextUp,
            y: (center.y + extent).nextUp,
            z: (center.z + extent).nextUp
        )
        guard minimum.x.isFinite,
              minimum.y.isFinite,
              minimum.z.isFinite,
              maximum.x.isFinite,
              maximum.y.isFinite,
              maximum.z.isFinite else {
            return nil
        }
        return try BoundingBox3D(
            minimum: minimum,
            maximum: maximum
        )
    }
}
