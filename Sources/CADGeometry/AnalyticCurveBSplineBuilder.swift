import CADCore
import Foundation

package struct AnalyticCurveBSplineBuilder {
    package init() {}

    package func boundedCurve(
        curve: Curve3D,
        interval: ScalarInterval,
        maximumSpanCount: Int,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D? {
        try curve.validate(tolerance: tolerance)
        guard maximumSpanCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Analytic curve conversion requires a positive rational span budget."
            )
        }
        guard try curve.parameterDomain.containsSpan(
            from: interval.lower,
            to: interval.upper,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Analytic curve conversion range exceeds the bounded source domain."
            )
        }

        switch curve {
        case let .line(line):
            return try lineCurve(
                origin: line.origin,
                direction: line.direction,
                interval: interval,
                tolerance: tolerance
            )
        case let .circle(circle):
            let normal = try circle.normal.normalized(tolerance: tolerance.distance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let cosineAxis = try helper.cross(normal).normalized(
                tolerance: tolerance.distance
            )
            return try conicCurve(
                center: circle.center,
                cosine: cosineAxis * circle.radius,
                sine: normal.cross(cosineAxis) * circle.radius,
                interval: interval,
                maximumSpanCount: maximumSpanCount,
                tolerance: tolerance
            )
        case let .analytic(analytic):
            switch analytic {
            case let .line(origin, direction):
                return try lineCurve(
                    origin: origin,
                    direction: direction,
                    interval: interval,
                    tolerance: tolerance
                )
            case let .circle(center, normal, radius),
                 let .arc(center, normal, radius, _, _):
                let basis = try analyticOrthonormalBasis(
                    normal,
                    tolerance: tolerance
                )
                return try conicCurve(
                    center: center,
                    cosine: basis.u * radius,
                    sine: basis.v * radius,
                    interval: interval,
                    maximumSpanCount: maximumSpanCount,
                    tolerance: tolerance
                )
            case let .ellipse(
                center,
                normal,
                majorAxis,
                majorRadius,
                minorRadius
            ):
                let minorAxis = try normal.cross(majorAxis).normalized(
                    tolerance: tolerance.distance
                )
                return try conicCurve(
                    center: center,
                    cosine: majorAxis * majorRadius,
                    sine: minorAxis * minorRadius,
                    interval: interval,
                    maximumSpanCount: maximumSpanCount,
                    tolerance: tolerance
                )
            case let .hyperbola(curve):
                return try hyperbolaCurve(
                    curve,
                    interval: interval,
                    maximumSpanCount: maximumSpanCount,
                    tolerance: tolerance
                )
            case let .parabola(curve):
                return try parabolaCurve(
                    curve,
                    interval: interval,
                    tolerance: tolerance
                )
            case .planeTorus:
                return nil
            }
        case .bSpline, .implicit, .surfaceLift:
            return nil
        }
    }

    private func lineCurve(
        origin: Point3D,
        direction: Vector3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        let result = BSplineCurve3D(
            degree: 1,
            knots: [interval.lower, interval.lower, interval.upper, interval.upper],
            controlPoints: [
                origin + direction * interval.lower,
                origin + direction * interval.upper,
            ],
            weights: [1.0, 1.0]
        )
        try result.validate(tolerance: tolerance)
        return result
    }

    private func conicCurve(
        center: Point3D,
        cosine: Vector3D,
        sine: Vector3D,
        interval: ScalarInterval,
        maximumSpanCount: Int,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        let maximumAnglePerSpan = Double.pi * 0.5
        let rawSpanCount = ceil(interval.width / maximumAnglePerSpan)
        guard rawSpanCount.isFinite,
              rawSpanCount <= Double(maximumSpanCount),
              rawSpanCount <= Double(Int.max) else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: rawSpanCount,
                tolerance: tolerance,
                message: "Exact conic conversion exceeded its rational span budget."
            )
        }
        let spanCount = max(1, Int(rawSpanCount))
        var controlPoints: [Point3D] = []
        var weights: [Double] = []
        var knots = Array(repeating: interval.lower, count: 3)
        controlPoints.reserveCapacity(spanCount * 2 + 1)
        weights.reserveCapacity(spanCount * 2 + 1)
        knots.reserveCapacity(spanCount * 2 + 4)

        for spanIndex in 0..<spanCount {
            let lowerFraction = Double(spanIndex) / Double(spanCount)
            let upperFraction = Double(spanIndex + 1) / Double(spanCount)
            let lower = interval.lower + interval.width * lowerFraction
            let upper = interval.lower + interval.width * upperFraction
            let middle = lower + (upper - lower) * 0.5
            let middleWeight = cos((upper - lower) * 0.5)
            guard middleWeight.isFinite,
                  middleWeight > Double.ulpOfOne else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: middleWeight,
                    tolerance: tolerance,
                    message: "Exact conic conversion produced a non-positive middle weight."
                )
            }
            if spanIndex == 0 {
                controlPoints.append(point(
                    center: center,
                    cosine: cosine,
                    sine: sine,
                    angle: lower,
                    radialScale: 1.0
                ))
                weights.append(1.0)
            }
            controlPoints.append(point(
                center: center,
                cosine: cosine,
                sine: sine,
                angle: middle,
                radialScale: 1.0 / middleWeight
            ))
            weights.append(middleWeight)
            controlPoints.append(point(
                center: center,
                cosine: cosine,
                sine: sine,
                angle: upper,
                radialScale: 1.0
            ))
            weights.append(1.0)
            if spanIndex + 1 < spanCount {
                knots.append(contentsOf: [upper, upper])
            }
        }
        knots.append(contentsOf: Array(repeating: interval.upper, count: 3))
        let result = BSplineCurve3D(
            degree: 2,
            knots: knots,
            controlPoints: controlPoints,
            weights: weights
        )
        try result.validate(tolerance: tolerance)
        try verifyLocus(
            result,
            center: center,
            cosine: cosine,
            sine: sine,
            interval: interval,
            spanCount: spanCount,
            tolerance: tolerance
        )
        return result
    }

    private func hyperbolaCurve(
        _ curve: Hyperbola3D,
        interval: ScalarInterval,
        maximumSpanCount: Int,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        let rawSpanCount = ceil(interval.width)
        guard rawSpanCount.isFinite,
              rawSpanCount <= Double(maximumSpanCount),
              rawSpanCount <= Double(Int.max) else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: rawSpanCount,
                tolerance: tolerance,
                message: "Exact hyperbola conversion exceeded its rational span budget."
            )
        }
        let spanCount = max(1, Int(rawSpanCount))
        let conjugateAxis = try curve.normal.cross(curve.transverseAxis).normalized(
            tolerance: tolerance.distance
        )
        let cosine = curve.transverseAxis * curve.transverseRadius
        let sine = conjugateAxis * curve.conjugateRadius
        var controlPoints: [Point3D] = []
        var weights: [Double] = []
        var knots = Array(repeating: interval.lower, count: 3)
        controlPoints.reserveCapacity(spanCount * 2 + 1)
        weights.reserveCapacity(spanCount * 2 + 1)
        knots.reserveCapacity(spanCount * 2 + 4)

        for spanIndex in 0..<spanCount {
            let lower = interval.lower
                + interval.width * Double(spanIndex) / Double(spanCount)
            let upper = interval.lower
                + interval.width * Double(spanIndex + 1) / Double(spanCount)
            let middle = 0.5 * (lower + upper)
            let middleWeight = cosh(0.5 * (upper - lower))
            guard middleWeight.isFinite, middleWeight > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: middleWeight,
                    tolerance: tolerance,
                    message: "Exact hyperbola conversion exceeded finite rational weights."
                )
            }
            if spanIndex == 0 {
                controlPoints.append(hyperbolaPoint(
                    center: curve.center,
                    cosine: cosine,
                    sine: sine,
                    parameter: lower,
                    radialScale: 1.0
                ))
                weights.append(1.0)
            }
            controlPoints.append(hyperbolaPoint(
                center: curve.center,
                cosine: cosine,
                sine: sine,
                parameter: middle,
                radialScale: 1.0 / middleWeight
            ))
            weights.append(middleWeight)
            controlPoints.append(hyperbolaPoint(
                center: curve.center,
                cosine: cosine,
                sine: sine,
                parameter: upper,
                radialScale: 1.0
            ))
            weights.append(1.0)
            if spanIndex + 1 < spanCount {
                knots.append(contentsOf: [upper, upper])
            }
        }
        knots.append(contentsOf: Array(repeating: interval.upper, count: 3))
        let result = BSplineCurve3D(
            degree: 2,
            knots: knots,
            controlPoints: controlPoints,
            weights: weights
        )
        try result.validate(tolerance: tolerance)
        try verifyHyperbolaLocus(
            result,
            curve: curve,
            interval: interval,
            spanCount: spanCount,
            tolerance: tolerance
        )
        return result
    }

    private func parabolaCurve(
        _ curve: Parabola3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        let start = try curve.differentialGeometry(
            at: interval.lower,
            tolerance: tolerance
        )
        let end = try curve.differentialGeometry(
            at: interval.upper,
            tolerance: tolerance
        )
        let result = BSplineCurve3D(
            degree: 2,
            knots: [
                interval.lower,
                interval.lower,
                interval.lower,
                interval.upper,
                interval.upper,
                interval.upper,
            ],
            controlPoints: [
                start.position,
                start.position
                    + start.firstDerivative * (0.5 * interval.width),
                end.position,
            ],
            weights: [1.0, 1.0, 1.0]
        )
        try result.validate(tolerance: tolerance)
        return result
    }

    private func verifyHyperbolaLocus(
        _ curve: BSplineCurve3D,
        curve source: Hyperbola3D,
        interval: ScalarInterval,
        spanCount: Int,
        tolerance: ModelingTolerance
    ) throws {
        let conjugateAxis = try source.normal.cross(source.transverseAxis).normalized(
            tolerance: tolerance.distance
        )
        let modelScale = max(
            source.transverseRadius,
            source.conjugateRadius,
            1.0
        )
        var maximumResidual = 0.0
        for spanIndex in 0..<spanCount {
            let lower = interval.lower
                + interval.width * Double(spanIndex) / Double(spanCount)
            let upper = interval.lower
                + interval.width * Double(spanIndex + 1) / Double(spanCount)
            for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let parameter = lower + (upper - lower) * fraction
                let point = try curve.point(at: parameter, tolerance: tolerance)
                let offset = point - source.center
                let transverse = offset.dot(source.transverseAxis)
                    / source.transverseRadius
                let conjugate = offset.dot(conjugateAxis) / source.conjugateRadius
                maximumResidual = max(
                    maximumResidual,
                    abs(offset.dot(source.normal)).nextUp,
                    (abs(transverse * transverse - conjugate * conjugate - 1.0)
                        * modelScale).nextUp
                )
            }
        }
        guard maximumResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Exact hyperbola conversion failed its source-locus verification."
            )
        }
    }

    private func hyperbolaPoint(
        center: Point3D,
        cosine: Vector3D,
        sine: Vector3D,
        parameter: Double,
        radialScale: Double
    ) -> Point3D {
        center
            + cosine * (cosh(parameter) * radialScale)
            + sine * (sinh(parameter) * radialScale)
    }

    private func verifyLocus(
        _ curve: BSplineCurve3D,
        center: Point3D,
        cosine: Vector3D,
        sine: Vector3D,
        interval: ScalarInterval,
        spanCount: Int,
        tolerance: ModelingTolerance
    ) throws {
        let cosineSquared = cosine.dot(cosine)
        let sineSquared = sine.dot(sine)
        let normal = try cosine.cross(sine).normalized(
            tolerance: tolerance.distance * tolerance.distance
        )
        let modelScale = max(1.0, sqrt(cosineSquared), sqrt(sineSquared))
        var maximumResidual = 0.0
        for spanIndex in 0..<spanCount {
            let lower = interval.lower
                + interval.width * Double(spanIndex) / Double(spanCount)
            let upper = interval.lower
                + interval.width * Double(spanIndex + 1) / Double(spanCount)
            for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let parameter = lower + (upper - lower) * fraction
                let actual = try curve.point(at: parameter, tolerance: tolerance)
                let relative = actual - center
                let cosineCoordinate = relative.dot(cosine) / cosineSquared
                let sineCoordinate = relative.dot(sine) / sineSquared
                let reconstructed = center
                    + cosine * cosineCoordinate
                    + sine * sineCoordinate
                let planeResidual = abs(relative.dot(normal)).nextUp
                let conicResidual = (
                    abs(
                        cosineCoordinate * cosineCoordinate
                            + sineCoordinate * sineCoordinate
                            - 1.0
                    ) * modelScale
                ).nextUp
                maximumResidual = max(
                    maximumResidual,
                    planeResidual,
                    conicResidual,
                    (actual - reconstructed).length.nextUp
                )
            }
        }
        guard maximumResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Exact conic conversion failed its source-locus verification."
            )
        }
    }

    private func point(
        center: Point3D,
        cosine: Vector3D,
        sine: Vector3D,
        angle: Double,
        radialScale: Double
    ) -> Point3D {
        center
            + cosine * (cos(angle) * radialScale)
            + sine * (sin(angle) * radialScale)
    }
}
