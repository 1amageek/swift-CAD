import Foundation
import CADCore

struct PlaneTorusSurfaceIntersector {
    private struct TrigonometricPolynomial {
        let constant: Double
        let cosine: Double
        let sine: Double
        let cosineDouble: Double

        var coefficientScale: Double {
            max(
                abs(constant),
                abs(cosine),
                abs(sine),
                abs(cosineDouble),
                1.0
            )
        }

        func value(at angle: Double) -> Double {
            constant
                + cosine * cos(angle)
                + sine * sin(angle)
                + cosineDouble * cos(2.0 * angle)
        }

        func derivative(at angle: Double) -> Double {
            -cosine * sin(angle)
                + sine * cos(angle)
                - 2.0 * cosineDouble * sin(2.0 * angle)
        }

        var tangentHalfAngleCoefficients: [Double] {
            [
                constant + cosine + cosineDouble,
                2.0 * sine,
                2.0 * constant - 6.0 * cosineDouble,
                2.0 * sine,
                constant - cosine + cosineDouble,
            ]
        }
    }

    private struct Configuration {
        let torusSurface: Surface3D
        let torus: CanonicalAnalyticSurface.Torus
        let radialNormalLength: Double
        let axialNormal: Double
        let centerDistance: Double
        let majorAnglePhase: Double
        let discriminant: TrigonometricPolynomial

        var characteristicLength: Double {
            max(
                torus.majorRadius + torus.minorRadius,
                abs(centerDistance),
                1.0
            )
        }

        func point(
            minorAngle: Double,
            branchSign: Double,
            classificationTolerance: Double,
            tolerance: ModelingTolerance
        ) throws -> Point3D {
            let radialScale = torus.majorRadius
                + torus.minorRadius * cos(minorAngle)
            let numerator = -centerDistance
                - torus.minorRadius * axialNormal * sin(minorAngle)
            let denominator = radialScale * radialNormalLength
            guard denominator > tolerance.distance * radialNormalLength else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: denominator,
                    tolerance: tolerance,
                    message: "Plane-torus tracing encountered a collapsed radial denominator."
                )
            }
            let ratio = numerator / denominator
            let ratioTolerance = classificationTolerance
                / max(denominator * denominator, Double.ulpOfOne)
            guard abs(ratio) <= 1.0 + ratioTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: abs(ratio) - 1.0,
                    tolerance: tolerance,
                    message: "Plane-torus tracing left its certified minor-angle interval."
                )
            }
            let majorAngle = majorAnglePhase
                + branchSign * acos(min(max(ratio, -1.0), 1.0))
            return try torusSurface.point(
                u: majorAngle,
                v: minorAngle,
                tolerance: tolerance
            )
        }
    }

    private struct ValidMinorAngleInterval {
        let lower: Double
        let upper: Double
    }

    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        plane: CanonicalAnalyticSurface.Plane,
        torus: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let axisProjection = plane.normal.dot(torus.axis)
        let radialNormal = plane.normal - torus.axis * axisProjection
        let radialNormalLength = radialNormal.length
        let centerDistance = (torus.center - plane.origin).dot(plane.normal)

        if radialNormalLength <= tolerance.angle {
            return try axialSection(
                plane: plane,
                torus: torus,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }

        if abs(axisProjection) <= tolerance.angle,
           abs(centerDistance) <= tolerance.distance {
            let radialDirection = try torus.axis.cross(plane.normal).normalized(
                tolerance: tolerance.distance
            )
            return try [-1.0, 1.0].map { sign in
                try verifier.curve(
                    .circle(Circle3D(
                        center: torus.center + radialDirection * (sign * torus.majorRadius),
                        normal: plane.normal,
                        radius: torus.minorRadius
                    )),
                    kind: .transverse,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                    tolerance: tolerance
                )
            }
        }

        let support = torus.majorRadius * radialNormalLength + torus.minorRadius
        let absoluteDistance = abs(centerDistance)
        guard absoluteDistance <= support + tolerance.distance else { return [] }
        if abs(absoluteDistance - support) <= tolerance.distance {
            let targetSign = centerDistance > 0.0 ? -1.0 : 1.0
            let radialDirection = try radialNormal.normalized(tolerance: tolerance.distance)
            let point = torus.center
                + radialDirection * (targetSign * torus.majorRadius)
                + plane.normal * (targetSign * torus.minorRadius)
            return [try verifier.point(
                point,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )]
        }

        return try generalSection(
            plane: plane,
            torus: torus,
            radialNormalLength: radialNormalLength,
            axisProjection: axisProjection,
            centerDistance: centerDistance,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )
    }

    private func generalSection(
        plane: CanonicalAnalyticSurface.Plane,
        torus: CanonicalAnalyticSurface.Torus,
        radialNormalLength: Double,
        axisProjection: Double,
        centerDistance: Double,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let configuration = try configuration(
            plane: plane,
            torus: torus,
            radialNormalLength: radialNormalLength,
            axisProjection: axisProjection,
            centerDistance: centerDistance,
            tolerance: tolerance
        )
        let classificationTolerance = max(
            tolerance.distance * configuration.characteristicLength * 8.0,
            Double.ulpOfOne * pow(configuration.characteristicLength, 2.0) * 2_048.0
        )
        let boundaries = try boundaryAngles(
            configuration: configuration,
            classificationTolerance: classificationTolerance,
            options: options,
            tolerance: tolerance
        )
        let splineBuilder = SurfaceIntersectionSplineBuilder(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )
        let period = 2.0 * Double.pi

        if boundaries.isEmpty {
            let value = configuration.discriminant.value(at: 0.0)
            if value < -classificationTolerance {
                return []
            }
            guard value > classificationTolerance else {
                throw singularSection(
                    residual: abs(value),
                    tolerance: tolerance,
                    message: "Plane-torus section has an unresolved full-domain tangency."
                )
            }
            return try [-1.0, 1.0].map { branchSign in
                try splineBuilder.intersection(
                    parameterRange: 0.0...period,
                    initialBreaks: uniformBreaks(lower: 0.0, upper: period, count: 32),
                    kind: .transverse,
                    pointAt: { parameter in
                        try configuration.point(
                            minorAngle: parameter,
                            branchSign: branchSign,
                            classificationTolerance: classificationTolerance,
                            tolerance: tolerance
                        )
                    }
                )
            }
        }

        let intervals = try validIntervals(
            boundaries: boundaries,
            configuration: configuration,
            classificationTolerance: classificationTolerance,
            tolerance: tolerance
        )
        return try intervals.map { interval in
            let midpoint = interval.lower + (interval.upper - interval.lower) * 0.5
            let halfSpan = (interval.upper - interval.lower) * 0.5
            return try splineBuilder.intersection(
                parameterRange: 0.0...period,
                initialBreaks: uniformBreaks(lower: 0.0, upper: period, count: 64),
                kind: .transverse,
                pointAt: { parameter in
                    let minorAngle = midpoint - halfSpan * cos(parameter)
                    let branchSign = sin(parameter) >= 0.0 ? 1.0 : -1.0
                    return try configuration.point(
                        minorAngle: minorAngle,
                        branchSign: branchSign,
                        classificationTolerance: classificationTolerance,
                        tolerance: tolerance
                    )
                }
            )
        }
    }

    private func configuration(
        plane: CanonicalAnalyticSurface.Plane,
        torus: CanonicalAnalyticSurface.Torus,
        radialNormalLength: Double,
        axisProjection: Double,
        centerDistance: Double,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        let torusSurface = Surface3D.analytic(.torus(
            center: torus.center,
            axis: torus.axis,
            majorRadius: torus.majorRadius,
            minorRadius: torus.minorRadius
        ))
        let radialU = try (
            torusSurface.point(u: 0.0, v: 0.0, tolerance: tolerance) - torus.center
        ).normalized(tolerance: tolerance.distance)
        let radialV = try (
            torusSurface.point(u: Double.pi * 0.5, v: 0.0, tolerance: tolerance)
                - torus.center
        ).normalized(tolerance: tolerance.distance)
        let radialCosine = plane.normal.dot(radialU)
        let radialSine = plane.normal.dot(radialV)
        let radialSquared = radialNormalLength * radialNormalLength
        let axialSquared = axisProjection * axisProjection
        let minorSquared = torus.minorRadius * torus.minorRadius
        let discriminant = TrigonometricPolynomial(
            constant: radialSquared * (
                torus.majorRadius * torus.majorRadius + minorSquared * 0.5
            ) - centerDistance * centerDistance - axialSquared * minorSquared * 0.5,
            cosine: 2.0 * radialSquared * torus.majorRadius * torus.minorRadius,
            sine: -2.0 * centerDistance * torus.minorRadius * axisProjection,
            cosineDouble: minorSquared * (radialSquared + axialSquared) * 0.5
        )
        return Configuration(
            torusSurface: torusSurface,
            torus: torus,
            radialNormalLength: radialNormalLength,
            axialNormal: axisProjection,
            centerDistance: centerDistance,
            majorAnglePhase: atan2(radialSine, radialCosine),
            discriminant: discriminant
        )
    }

    private func boundaryAngles(
        configuration: Configuration,
        classificationTolerance: Double,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let polynomial = configuration.discriminant
        let normalizedResidual = max(
            Double.ulpOfOne * 1_024.0,
            classificationTolerance / polynomial.coefficientScale
        )
        let solver = try RealPolynomialRootSolver(
            rootTolerance: max(tolerance.angle * 0.25, Double.ulpOfOne * 1_024.0),
            residualTolerance: normalizedResidual,
            coefficientTolerance: Double.ulpOfOne * 128.0
        )
        let tangentRoots = try solver.realRoots(
            coefficients: polynomial.tangentHalfAngleCoefficients
        )
        guard tangentRoots.count <= options.maximumSeedCount else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Plane-torus section exceeded its quartic boundary root limit."
            )
        }
        var values = tangentRoots.map {
            normalizedAngle(2.0 * atan($0))
        }
        if abs(polynomial.value(at: Double.pi)) <= classificationTolerance {
            values.append(Double.pi)
        }
        values = values.map {
            refinedAngle(
                $0,
                polynomial: polynomial,
                maximumIterations: options.maximumIterations,
                residualTolerance: classificationTolerance * 1.0e-8,
                tolerance: tolerance
            )
        }.filter {
            abs(polynomial.value(at: $0)) <= classificationTolerance * 16.0
        }.sorted()

        var result: [Double] = []
        for value in values {
            if result.last.map({ angularDistance($0, value) <= tolerance.angle }) != true {
                result.append(value)
            }
        }
        if result.count > 1,
           let first = result.first,
           let last = result.last,
           angularDistance(first, last) <= tolerance.angle {
            result.removeLast()
        }
        let derivativeThreshold = max(
            tolerance.distance * configuration.characteristicLength * 8.0,
            Double.ulpOfOne * pow(configuration.characteristicLength, 2.0) * 2_048.0
        )
        for angle in result {
            let derivative = abs(polynomial.derivative(at: angle))
            guard derivative > derivativeThreshold else {
                throw singularSection(
                    residual: derivative,
                    tolerance: tolerance,
                    message: "Plane-torus section contains a singular or tangent quartic boundary."
                )
            }
        }
        return result
    }

    private func validIntervals(
        boundaries: [Double],
        configuration: Configuration,
        classificationTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> [ValidMinorAngleInterval] {
        let period = 2.0 * Double.pi
        var result: [ValidMinorAngleInterval] = []
        for index in boundaries.indices {
            let lower = boundaries[index]
            let upper = index + 1 < boundaries.count
                ? boundaries[index + 1]
                : boundaries[0] + period
            let midpoint = lower + (upper - lower) * 0.5
            let value = configuration.discriminant.value(at: midpoint)
            if value > classificationTolerance {
                result.append(ValidMinorAngleInterval(lower: lower, upper: upper))
            } else if abs(value) <= classificationTolerance {
                throw singularSection(
                    residual: abs(value),
                    tolerance: tolerance,
                    message: "Plane-torus quartic interval could not be classified away from zero."
                )
            }
        }
        return result
    }

    private func refinedAngle(
        _ initial: Double,
        polynomial: TrigonometricPolynomial,
        maximumIterations: Int,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        var angle = normalizedAngle(initial)
        let effectiveResidual = max(
            residualTolerance,
            Double.ulpOfOne * polynomial.coefficientScale * 128.0
        )
        for _ in 0..<maximumIterations {
            let value = polynomial.value(at: angle)
            if abs(value) <= effectiveResidual { break }
            let derivative = polynomial.derivative(at: angle)
            guard abs(derivative) > tolerance.angle * polynomial.coefficientScale else {
                break
            }
            let step = value / derivative
            guard step.isFinite, abs(step) <= Double.pi * 0.5 else { break }
            angle = normalizedAngle(angle - step)
            if abs(step) <= Double.ulpOfOne * max(abs(angle), 1.0) * 128.0 {
                break
            }
        }
        return angle
    }

    private func uniformBreaks(
        lower: Double,
        upper: Double,
        count: Int
    ) -> [Double] {
        (0...count).map {
            lower + (upper - lower) * Double($0) / Double(count)
        }
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        let period = 2.0 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }

    private func angularDistance(_ first: Double, _ second: Double) -> Double {
        let period = 2.0 * Double.pi
        let difference = abs(first - second).truncatingRemainder(dividingBy: period)
        return min(difference, period - difference)
    }

    private func singularSection(
        residual: Double,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .singularSystem,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }

    private func axialSection(
        plane: CanonicalAnalyticSurface.Plane,
        torus: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let height = (plane.origin - torus.center).dot(torus.axis)
        guard abs(height) <= torus.minorRadius + tolerance.distance else { return [] }
        let radialOffset = sqrt(max(
            0.0,
            torus.minorRadius * torus.minorRadius - height * height
        ))
        let center = torus.center + torus.axis * height
        if radialOffset <= tolerance.distance {
            return [try verifier.curve(
                .circle(Circle3D(
                    center: center,
                    normal: plane.normal,
                    radius: torus.majorRadius
                )),
                kind: .tangent,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                tolerance: tolerance
            )]
        }
        return try [torus.majorRadius - radialOffset, torus.majorRadius + radialOffset].map { radius in
            try verifier.curve(
                .circle(Circle3D(center: center, normal: plane.normal, radius: radius)),
                kind: .transverse,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                sampleParameters: SurfaceSurfaceIntersectionVerifier.closedCurveSamples,
                tolerance: tolerance
            )
        }
    }
}
