import CADCore
import CADGeometry
import Foundation

struct CertifiedAnalyticImplicitPcurveAreaIntegrator {
    func bounds(
        for curve: CertifiedAnalyticImplicitSurfaceParameterCurve,
        uShift: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAreaBounds {
        let intersection = curve.intersection
        try intersection.validate(tolerance: tolerance)
        let implicit = intersection.implicitCurve
        let analyticU: SurfaceIntersectionParameterCoordinate = intersection.analyticIsFirst
            ? .firstU
            : .secondU
        let analyticV: SurfaceIntersectionParameterCoordinate = intersection.analyticIsFirst
            ? .firstV
            : .secondV
        guard implicit.cells.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified analytic pcurve area requires at least one graph cell."
            )
        }
        let ascendingStart = min(curve.startFraction, curve.endFraction)
        let ascendingEnd = max(curve.startFraction, curve.endFraction)
        let cellCount = implicit.cells.count
        var result = SurfaceParameterAreaBounds.zero
        for (index, cell) in implicit.cells.enumerated() {
            let cellStart = Double(index) / Double(cellCount)
            let cellEnd = Double(index + 1) / Double(cellCount)
            let overlapStart = max(ascendingStart, cellStart)
            let overlapEnd = min(ascendingEnd, cellEnd)
            guard overlapEnd - overlapStart > tolerance.relative else {
                continue
            }
            let analyticUBounds = try circleAngleBounds(
                cell.parameterBox.interval(for: analyticU),
                offset: intersection.periodicSeamOffset,
                parameterUpperBound: 4.0,
                tolerance: tolerance
            )
            let sourceDerivatives = try cell.parameterDerivativeBounds(
                firstSurface: implicit.firstSurface,
                secondSurface: implicit.secondSurface,
                tolerance: tolerance
            )
            let analyticVDerivative: ScalarInterval
            switch intersection.analyticSurface {
            case .cylinder, .analytic(.cylinder), .analytic(.cone):
                analyticVDerivative = sourceDerivatives[analyticV.rawValue]
            case .analytic(.sphere):
                _ = try circleAngleBounds(
                    cell.parameterBox.interval(for: analyticV),
                    offset: -Double.pi * 0.5,
                    parameterUpperBound: 2.0,
                    tolerance: tolerance
                )
                analyticVDerivative = try circleAngleDerivativeBounds(
                    multipliedBy: sourceDerivatives[analyticV.rawValue]
                )
            case .analytic(.torus):
                _ = try circleAngleBounds(
                    cell.parameterBox.interval(for: analyticV),
                    offset: intersection.periodicSeamOffset,
                    parameterUpperBound: 4.0,
                    tolerance: tolerance
                )
                analyticVDerivative = try circleAngleDerivativeBounds(
                    multipliedBy: sourceDerivatives[analyticV.rawValue]
                )
            case .plane, .analytic(.plane), .bSpline:
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Certified analytic pcurve area received a non-periodic source surface."
                )
            }
            let integrand = intervalProductBounds(
                lower: (analyticUBounds.lower + uShift).nextDown,
                upper: (analyticUBounds.upper + uShift).nextUp,
                scalarLower: analyticVDerivative.lower,
                scalarUpper: analyticVDerivative.upper
            )
            let cellLocalSpan = (overlapEnd - overlapStart) * Double(cellCount)
            result = result.adding(intervalProductBounds(
                lower: integrand.lower,
                upper: integrand.upper,
                scalarLower: cellLocalSpan.nextDown,
                scalarUpper: cellLocalSpan.nextUp
            ))
        }
        guard curve.startFraction <= curve.endFraction else {
            return SurfaceParameterAreaBounds(
                lower: (-result.upper).nextDown,
                upper: (-result.lower).nextUp
            )
        }
        return result
    }

    private func circleAngleBounds(
        _ parameter: ScalarInterval,
        offset: Double,
        parameterUpperBound: Double,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard parameter.lower >= -tolerance.relative,
              parameter.upper <= parameterUpperBound + tolerance.relative else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An analytic NURBS circle parameter left its certified conversion domain."
            )
        }
        let lower = circleAngle(
            at: min(max(parameter.lower, 0.0), parameterUpperBound)
        ) + offset
        let upper = circleAngle(
            at: min(max(parameter.upper, 0.0), parameterUpperBound)
        ) + offset
        guard lower.isFinite, upper.isFinite, lower <= upper else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "An analytic NURBS circle parameter lost monotone angle order."
            )
        }
        return try ScalarInterval(lower: lower.nextDown, upper: upper.nextUp)
    }

    private func circleAngle(at parameter: Double) -> Double {
        if parameter >= 4.0 {
            return 2.0 * Double.pi
        }
        let segment = min(max(Int(floor(parameter)), 0), 3)
        let local = parameter - Double(segment)
        let complement = 1.0 - local
        let diagonalWeight = sqrt(0.5)
        let x = complement * complement
            + 2.0 * diagonalWeight * local * complement
        let y = 2.0 * diagonalWeight * local * complement
            + local * local
        return Double(segment) * Double.pi * 0.5 + atan2(y, x)
    }

    private func circleAngleDerivativeBounds(
        multipliedBy derivative: ScalarInterval
    ) throws -> ScalarInterval {
        // Every rational quadratic quarter-circle span has a positive angle
        // derivative in [sqrt(2), 4(sqrt(2) - 1)]. [1, 2] is an
        // outward-conservative enclosure that remains valid at joined knots.
        let lowerScale = 1.0.nextDown
        let upperScale = 2.0.nextUp
        let products = [
            derivative.lower * lowerScale,
            derivative.lower * upperScale,
            derivative.upper * lowerScale,
            derivative.upper * upperScale,
        ]
        return try ScalarInterval(
            lower: (products.min() ?? -.infinity).nextDown,
            upper: (products.max() ?? .infinity).nextUp
        )
    }

    private func intervalProductBounds(
        lower: Double,
        upper: Double,
        scalarLower: Double,
        scalarUpper: Double
    ) -> SurfaceParameterAreaBounds {
        let products = [
            lower * scalarLower,
            lower * scalarUpper,
            upper * scalarLower,
            upper * scalarUpper,
        ]
        return SurfaceParameterAreaBounds(
            lower: (products.min() ?? -.infinity).nextDown,
            upper: (products.max() ?? .infinity).nextUp
        )
    }
}
