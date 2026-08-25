import CADCore

extension SurfaceParameterCurve {
    /// Returns the second exact support of a certified intersection pcurve.
    ///
    /// The receiver is the parameter-space representation on `hostingSurface`.
    /// A non-`nil` result certifies that the lifted curve is the intersection
    /// of `hostingSurface` and the returned surface. Curves without retained
    /// two-surface provenance deliberately return `nil`.
    package func otherIntersectionSupportSurface(
        on hostingSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Surface3D? {
        try tolerance.validate()
        switch self {
        case let .certifiedImplicit(curve):
            let expectedHostingSurface: Surface3D
            switch curve.role {
            case .first:
                expectedHostingSurface = .bSpline(curve.intersection.firstSurface)
                guard hostingSurface == expectedHostingSurface else {
                    throw supportSurfaceMismatch(tolerance: tolerance)
                }
                return .bSpline(curve.intersection.secondSurface)
            case .second:
                expectedHostingSurface = .bSpline(curve.intersection.secondSurface)
                guard hostingSurface == expectedHostingSurface else {
                    throw supportSurfaceMismatch(tolerance: tolerance)
                }
                return .bSpline(curve.intersection.firstSurface)
            }
        case let .certifiedAnalyticImplicit(curve):
            guard hostingSurface == curve.intersection.analyticSurface else {
                throw supportSurfaceMismatch(tolerance: tolerance)
            }
            return .bSpline(curve.intersection.boundedSurface)
        case let .certifiedAnalyticPair(curve):
            guard hostingSurface == curve.intersection.surface(for: curve.role) else {
                throw supportSurfaceMismatch(tolerance: tolerance)
            }
            switch curve.role {
            case .first:
                return curve.intersection.secondSurface
            case .second:
                return curve.intersection.firstSurface
            }
        case let .rigidImage(curve):
            guard hostingSurface == curve.targetSurface else {
                throw supportSurfaceMismatch(tolerance: tolerance)
            }
            guard let sourceSupport = try curve.source.parameterCurve
                .otherIntersectionSupportSurface(
                    on: curve.source.surface,
                    tolerance: tolerance
                ) else {
                return nil
            }
            return try curve.transform.applying(
                to: sourceSupport,
                tolerance: tolerance
            )
        case let .offsetSurfaceImage(curve):
            guard hostingSurface == (try curve.targetSurface(tolerance: tolerance)) else {
                throw supportSurfaceMismatch(tolerance: tolerance)
            }
            return nil
        case let .periodicTranslation(base, _, _):
            return try base.otherIntersectionSupportSurface(
                on: hostingSurface,
                tolerance: tolerance
            )
        case .affine, .constantU, .constantV, .harmonic,
             .sphericalGreatCircle, .polyline, .bSpline,
             .projectedAnalytic:
            return nil
        }
    }

    private func supportSurfaceMismatch(
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .invalidInput,
            tolerance: tolerance,
            message: "Certified intersection provenance does not belong to the requested hosting surface."
        )
    }

    /// Returns the full-branch box retained by certified intersection truth.
    /// A face-local cache without such truth returns `nil`.
    package func exactIntersectionBoundingBox(
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D? {
        try tolerance.validate()
        switch self {
        case let .certifiedImplicit(curve):
            return try implicitIntersectionBoundingBox(
                curve.intersection,
                startFraction: curve.startFraction,
                endFraction: curve.endFraction,
                tolerance: tolerance
            )
        case let .certifiedAnalyticImplicit(curve):
            return try implicitIntersectionBoundingBox(
                curve.intersection.implicitCurve,
                startFraction: curve.startFraction,
                endFraction: curve.endFraction,
                tolerance: tolerance
            )
        case let .certifiedAnalyticPair(curve):
            return try curve.intersection.boundingBox(tolerance: tolerance)
        case let .rigidImage(curve):
            let interval = try ScalarInterval(lower: 0.0, upper: 1.0)
            let sourceBounds = try curve.source.boundingBox(
                over: interval,
                tolerance: tolerance
            )
            return try BoundingBox3D(
                points: boundingBoxCorners(sourceBounds).map(
                    curve.transform.applying(to:)
                )
            ).expanded(by: tolerance.distance)
        case .offsetSurfaceImage:
            return nil
        case let .periodicTranslation(base, _, _):
            return try base.exactIntersectionBoundingBox(
                tolerance: tolerance
            )
        case .affine, .constantU, .constantV, .harmonic,
             .sphericalGreatCircle, .polyline, .bSpline,
             .projectedAnalytic:
            return nil
        }
    }

    private func implicitIntersectionBoundingBox(
        _ intersection: CertifiedImplicitIntersectionCurve,
        startFraction: Double,
        endFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        let lower = min(startFraction, endFraction)
        let upper = max(startFraction, endFraction)
        if upper <= 1.0 {
            return try intersection.boundingBox(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                tolerance: tolerance
            )
        }
        if lower >= 1.0 {
            return try intersection.boundingBox(
                fromNormalizedFraction: lower - 1.0,
                toNormalizedFraction: upper - 1.0,
                tolerance: tolerance
            )
        }
        let first = try intersection.boundingBox(
            fromNormalizedFraction: lower,
            toNormalizedFraction: 1.0,
            tolerance: tolerance
        )
        let second = try intersection.boundingBox(
            fromNormalizedFraction: 0.0,
            toNormalizedFraction: upper - 1.0,
            tolerance: tolerance
        )
        return try first.union(second)
    }

    private func boundingBoxCorners(
        _ bounds: BoundingBox3D
    ) -> [Point3D] {
        [
            Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.minimum.z),
            Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.maximum.z),
            Point3D(x: bounds.minimum.x, y: bounds.maximum.y, z: bounds.minimum.z),
            Point3D(x: bounds.minimum.x, y: bounds.maximum.y, z: bounds.maximum.z),
            Point3D(x: bounds.maximum.x, y: bounds.minimum.y, z: bounds.minimum.z),
            Point3D(x: bounds.maximum.x, y: bounds.minimum.y, z: bounds.maximum.z),
            Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.minimum.z),
            Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.maximum.z),
        ]
    }
}
