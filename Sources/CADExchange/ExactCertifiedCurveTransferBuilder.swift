import CADCore
import CADGeometry
import CADTopology

/// Builds the verified rational transfer representation used by neutral CAD formats.
struct ExactCertifiedCurveTransferBuilder {
    private struct SupportData {
        let first: Surface3D
        let second: Surface3D
        let firstParameterAt: (Double) throws -> SurfaceParameter
        let secondParameterAt: (Double) throws -> SurfaceParameter
    }

    struct Result: Sendable {
        let curve: BSplineCurve3D
        let firstSurface: Surface3D
        let secondSurface: Surface3D
        let firstSurfaceParameterCurve: SurfaceParameterCurve
        let secondSurfaceParameterCurve: SurfaceParameterCurve
        let maximumResidualUpperBound: Double

        var representsSurfaceLift: Bool {
            firstSurface == secondSurface
        }
    }

    func build(
        curve: Curve3D,
        trim: CurveTrim,
        tolerance: ModelingTolerance
    ) throws -> Result {
        try tolerance.validate()
        try curve.validate(tolerance: tolerance)
        let lower = min(trim.startParameter, trim.endParameter)
        let upper = max(trim.startParameter, trim.endParameter)
        guard lower >= -tolerance.relative,
              upper <= 1.0 + tolerance.relative,
              upper - lower > tolerance.relative else {
            throw KernelError(
                phase: .exchange,
                code: .invalidInput,
                residual: upper - lower,
                tolerance: tolerance,
                message: "A certified curve transfer requires a non-degenerate normalized trim interval."
            )
        }
        let supports = try supportData(
            for: curve,
            tolerance: tolerance
        )
        let segmentCount = 16
        let breaks = (0...segmentCount).map { index in
            lower + (upper - lower) * Double(index) / Double(segmentCount)
        }
        let start = try curve.point(at: lower, tolerance: tolerance)
        let end = try curve.point(at: upper, tolerance: tolerance)
        let isClosed = lower <= tolerance.relative
            && upper >= 1.0 - tolerance.relative
            && start.isApproximatelyEqual(to: end, tolerance: tolerance.distance)
        let transferred = try SurfaceIntersectionSplineBuilder(
            firstSurface: supports.first,
            secondSurface: supports.second,
            options: SurfaceSurfaceIntersectionOptions(),
            tolerance: tolerance
        ).representation(
            parameterRange: lower...upper,
            initialBreaks: breaks,
            isClosed: isClosed,
            firstParameterAt: supports.firstParameterAt,
            secondParameterAt: supports.secondParameterAt,
            pointFirstDerivativeAt: { parameter in
                try curve.differentialGeometry(
                    at: parameter,
                    tolerance: tolerance
                ).firstDerivative
            },
            pointAt: { parameter in
                try curve.point(at: parameter, tolerance: tolerance)
            }
        )
        return Result(
            curve: transferred.curve,
            firstSurface: supports.first,
            secondSurface: supports.second,
            firstSurfaceParameterCurve: transferred.firstSurfaceParameterCurve,
            secondSurfaceParameterCurve: transferred.secondSurfaceParameterCurve,
            maximumResidualUpperBound: transferred.maximumResidual
        )
    }

    private func supportData(
        for curve: Curve3D,
        tolerance: ModelingTolerance
    ) throws -> SupportData {
        switch curve {
        case let .implicit(implicit):
            return SupportData(
                first: .bSpline(implicit.firstSurface),
                second: .bSpline(implicit.secondSurface),
                firstParameterAt: { parameter in
                    try implicit.parameterPair(
                        atNormalizedFraction: parameter,
                        tolerance: tolerance
                    ).first
                },
                secondParameterAt: { parameter in
                    try implicit.parameterPair(
                        atNormalizedFraction: parameter,
                        tolerance: tolerance
                    ).second
                }
            )
        case let .surfaceLift(lift):
            return SupportData(
                first: lift.surface,
                second: lift.surface,
                firstParameterAt: { parameter in
                    try lift.parameterCurve.parameter(
                        atNormalizedFraction: parameter,
                        tolerance: tolerance
                    )
                },
                secondParameterAt: { parameter in
                    try lift.parameterCurve.parameter(
                        atNormalizedFraction: parameter,
                        tolerance: tolerance
                    )
                }
            )
        case let .certifiedIntersection(certified):
            let supports = certified.supportSurfaces
            return SupportData(
                first: supports.first,
                second: supports.second,
                firstParameterAt: { parameter in
                    try certified.parameter(
                        on: supports.first,
                        atNormalizedFraction: parameter,
                        tolerance: tolerance
                    )
                },
                secondParameterAt: { parameter in
                    try certified.parameter(
                        on: supports.second,
                        atNormalizedFraction: parameter,
                        tolerance: tolerance
                    )
                }
            )
        case let .rigidImage(image):
            let source = try supportData(
                for: image.source,
                tolerance: tolerance
            )
            let firstTarget = try image.transform.applying(
                to: source.first,
                tolerance: tolerance
            )
            let secondTarget = try image.transform.applying(
                to: source.second,
                tolerance: tolerance
            )
            return SupportData(
                first: firstTarget,
                second: secondTarget,
                firstParameterAt: { parameter in
                    try transformedParameter(
                        sourceParameter: source.firstParameterAt(parameter),
                        sourceSurface: source.first,
                        targetSurface: firstTarget,
                        transform: image.transform,
                        targetPoint: curve.point(at: parameter, tolerance: tolerance),
                        tolerance: tolerance
                    )
                },
                secondParameterAt: { parameter in
                    try transformedParameter(
                        sourceParameter: source.secondParameterAt(parameter),
                        sourceSurface: source.second,
                        targetSurface: secondTarget,
                        transform: image.transform,
                        targetPoint: curve.point(at: parameter, tolerance: tolerance),
                        tolerance: tolerance
                    )
                }
            )
        case .line, .circle, .analytic, .bSpline, .affineImage:
            throw KernelError(
                phase: .exchange,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A certified transfer curve must retain one or two exact support surfaces."
            )
        }
    }

    private func transformedParameter(
        sourceParameter: SurfaceParameter,
        sourceSurface: Surface3D,
        targetSurface: Surface3D,
        transform: RigidTransform3D,
        targetPoint: Point3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        if let mapping = try transform.parameterAffineTransform(
            from: sourceSurface,
            to: targetSurface,
            tolerance: tolerance
        ) {
            return mapping.applying(to: sourceParameter)
        }
        let projection = try targetSurface.parameterProjection(
            of: targetPoint,
            tolerance: tolerance
        )
        return SurfaceParameter(u: projection.u, v: projection.v)
    }
}

private extension CertifiedIntersectionCurve3D {
    var supportSurfaces: (first: Surface3D, second: Surface3D) {
        switch self {
        case let .sphereCone(curve):
            (curve.sphereSurface, curve.coneSurface)
        case let .coneCone(curve):
            (curve.referenceSurface, curve.parameterizedSurface)
        case let .coneCylinder(curve):
            (curve.coneSurface, curve.cylinderSurface)
        case let .coneTorus(curve):
            (curve.coneSurface, curve.torusSurface)
        case let .parallelTorusTorus(curve):
            (curve.primarySurface, curve.secondarySurface)
        }
    }
}
