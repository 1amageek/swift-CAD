import CADCore

extension Curve3D {
    /// Returns the other exact surface that defines this intersection curve
    /// when `hostingSurface` is one of its retained supports.
    package func otherIntersectionSupportSurface(
        on hostingSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Surface3D? {
        try tolerance.validate()
        guard let supports = try intersectionSupportSurfaces(
            tolerance: tolerance
        ) else {
            return nil
        }
        let equivalence = DefaultAnalyticSurfaceEquivalenceResolver()
        if try equivalence.areEquivalent(
            hostingSurface,
            supports.first,
            tolerance: tolerance
        ) {
            return supports.second
        }
        if try equivalence.areEquivalent(
            hostingSurface,
            supports.second,
            tolerance: tolerance
        ) {
            return supports.first
        }
        return nil
    }

    private func intersectionSupportSurfaces(
        tolerance: ModelingTolerance
    ) throws -> (first: Surface3D, second: Surface3D)? {
        switch self {
        case let .analytic(.planeTorus(curve)):
            return (curve.planeSurface, curve.torusSurface)
        case let .implicit(curve):
            return (.bSpline(curve.firstSurface), .bSpline(curve.secondSurface))
        case let .surfaceLift(curve):
            guard let other = try curve.parameterCurve
                .otherIntersectionSupportSurface(
                    on: curve.surface,
                    tolerance: tolerance
                ) else {
                return nil
            }
            return (curve.surface, other)
        case let .certifiedIntersection(curve):
            switch curve {
            case let .sphereCone(source):
                return (source.sphereSurface, source.coneSurface)
            case let .coneCone(source):
                return (source.referenceSurface, source.parameterizedSurface)
            case let .coneCylinder(source):
                return (source.coneSurface, source.cylinderSurface)
            case let .coneTorus(source):
                return (source.coneSurface, source.torusSurface)
            case let .parallelTorusTorus(source):
                return (source.primarySurface, source.secondarySurface)
            }
        case let .rigidImage(curve):
            guard let sourceSupports = try curve.source
                .intersectionSupportSurfaces(tolerance: tolerance) else {
                return nil
            }
            return (
                try curve.transform.applying(
                    to: sourceSupports.first,
                    tolerance: tolerance
                ),
                try curve.transform.applying(
                    to: sourceSupports.second,
                    tolerance: tolerance
                )
            )
        case .line, .circle, .bSpline, .affineImage,
             .analytic(.line), .analytic(.circle), .analytic(.arc),
             .analytic(.ellipse), .analytic(.hyperbola),
             .analytic(.parabola):
            return nil
        }
    }
}
