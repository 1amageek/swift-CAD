import CADCore
import CADGeometry
import CADTopology

struct ExactSurfaceLiftTransferBuilder {
    struct Result: Sendable {
        let curve: BSplineCurve3D
        let parameterCurve: SurfaceParameterCurve
        let maximumResidualUpperBound: Double
    }

    func build(
        lift: SurfaceLiftCurve3D,
        trim: CurveTrim,
        tolerance: ModelingTolerance
    ) throws -> Result {
        try tolerance.validate()
        try lift.validate(tolerance: tolerance)
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
                message: "A surface-lift transfer requires a non-degenerate normalized trim interval."
            )
        }
        let segmentCount = 16
        let breaks = (0...segmentCount).map { index in
            lower + (upper - lower) * Double(index) / Double(segmentCount)
        }
        let start = try lift.point(atNormalizedFraction: lower, tolerance: tolerance)
        let end = try lift.point(atNormalizedFraction: upper, tolerance: tolerance)
        let isClosed = lower <= tolerance.relative
            && upper >= 1.0 - tolerance.relative
            && start.isApproximatelyEqual(to: end, tolerance: tolerance.distance)
        let transferred = try SurfaceIntersectionSplineBuilder(
            firstSurface: lift.surface,
            secondSurface: lift.surface,
            options: SurfaceSurfaceIntersectionOptions(),
            tolerance: tolerance
        ).representation(
            parameterRange: lower...upper,
            initialBreaks: breaks,
            isClosed: isClosed,
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
            },
            firstParameterDifferentialAt: { parameter in
                try lift.parameterCurve.differentialGeometry(
                    atNormalizedFraction: parameter,
                    tolerance: tolerance
                )
            },
            secondParameterDifferentialAt: { parameter in
                try lift.parameterCurve.differentialGeometry(
                    atNormalizedFraction: parameter,
                    tolerance: tolerance
                )
            },
            pointFirstDerivativeAt: { parameter in
                try lift.differentialGeometry(
                    atNormalizedFraction: parameter,
                    tolerance: tolerance
                ).firstDerivative
            },
            pointAt: { parameter in
                try lift.point(atNormalizedFraction: parameter, tolerance: tolerance)
            }
        )
        let parameterCurve = try lift.parameterCurve.subcurve(
            fromNormalizedFraction: lower,
            toNormalizedFraction: upper,
            tolerance: tolerance
        )
        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: .bSpline(transferred.curve),
            from: lower,
            to: upper,
            surface: lift.surface,
            parameterCurve: parameterCurve,
            options: CurveSurfaceCorrespondenceValidationOptions(
                maximumSubdivisionDepth: 24,
                maximumCellCount: 65_536
            ),
            tolerance: tolerance
        )
        return Result(
            curve: transferred.curve,
            parameterCurve: parameterCurve,
            maximumResidualUpperBound: transferred.maximumResidual
        )
    }
}
