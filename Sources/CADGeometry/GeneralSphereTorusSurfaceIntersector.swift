import Foundation
import CADCore

struct GeneralSphereTorusSurfaceIntersector {
    private struct Torus {
        let center: Point3D
        let axis: Vector3D
        let majorRadius: Double
        let minorRadius: Double

        var surface: Surface3D {
            .analytic(.torus(
                center: center,
                axis: axis,
                majorRadius: majorRadius,
                minorRadius: minorRadius
            ))
        }
    }

    private struct TrigonometricPolynomial {
        let constant: Double
        let cosine: Double
        let sine: Double
        let cosineDouble: Double
        let sineDouble: Double

        var coefficientScale: Double {
            max(
                abs(constant),
                abs(cosine),
                abs(sine),
                abs(cosineDouble),
                abs(sineDouble),
                1.0
            )
        }

        func value(at angle: Double) -> Double {
            constant
                + cosine * cos(angle)
                + sine * sin(angle)
                + cosineDouble * cos(2.0 * angle)
                + sineDouble * sin(2.0 * angle)
        }

        func derivative(at angle: Double) -> Double {
            -cosine * sin(angle)
                + sine * cos(angle)
                - 2.0 * cosineDouble * sin(2.0 * angle)
                + 2.0 * sineDouble * cos(2.0 * angle)
        }

        var tangentHalfAngleCoefficients: [Double] {
            [
                constant + cosine + cosineDouble,
                2.0 * sine + 4.0 * sineDouble,
                2.0 * constant - 6.0 * cosineDouble,
                2.0 * sine - 4.0 * sineDouble,
                constant - cosine + cosineDouble,
            ]
        }
    }

    private struct Configuration {
        let sphere: CanonicalAnalyticSurface.Sphere
        let torus: Torus
        let zeroRadial: Vector3D
        let quarterRadial: Vector3D
        let centerOffset: Vector3D
        let axialCoefficient: Double
        let discriminantPolynomial: TrigonometricPolynomial

        func radial(at angle: Double) -> Vector3D {
            zeroRadial * cos(angle) + quarterRadial * sin(angle)
        }

        func coefficients(at angle: Double) -> (cosine: Double, sine: Double, value: Double) {
            let radial = radial(at: angle)
            let radialOffset = centerOffset.dot(radial)
            let cosine = torus.majorRadius + radialOffset
            let sine = axialCoefficient
            let baseSquared = centerOffset.dot(centerOffset)
                + torus.majorRadius * torus.majorRadius
                + 2.0 * torus.majorRadius * radialOffset
            let value = (
                sphere.radius * sphere.radius
                    - baseSquared
                    - torus.minorRadius * torus.minorRadius
            ) / (2.0 * torus.minorRadius)
            return (cosine, sine, value)
        }

        func discriminant(at angle: Double) -> Double {
            discriminantPolynomial.value(at: angle)
        }
    }

    private struct AngularInterval {
        let lower: Double
        let upper: Double
    }

    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        sphere: CanonicalAnalyticSurface.Sphere,
        torus: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let sphereSurface: Surface3D
        let torusSurface: Surface3D
        if case .sphere = CanonicalAnalyticSurface(firstSurface) {
            sphereSurface = firstSurface
            torusSurface = secondSurface
        } else {
            sphereSurface = secondSurface
            torusSurface = firstSurface
        }
        let canonicalTorus = try canonicalTorus(torus, tolerance: tolerance)
        let radialCenterOffset = AnalyticAxisRelation.radialOffset(
            from: canonicalTorus.center,
            axis: canonicalTorus.axis,
            to: sphere.center
        )
        guard radialCenterOffset.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: radialCenterOffset.length,
                tolerance: tolerance,
                message: "General sphere-torus intersection requires a sphere center off the torus axis."
            )
        }
        try rejectSpherePoleContact(
            sphere: sphere,
            torus: canonicalTorus,
            tolerance: tolerance
        )
        let configuration = try makeConfiguration(
            sphere: sphere,
            torus: canonicalTorus,
            tolerance: tolerance
        )
        let roots = try boundaryAngles(
            configuration: configuration,
            options: options,
            tolerance: tolerance
        )
        let builder = SurfaceIntersectionSplineBuilder(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )

        if roots.isEmpty {
            guard isAllowed(
                angle: 0.0,
                configuration: configuration,
                tolerance: tolerance
            ) else {
                return []
            }
            let residualTolerance = classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            )
            let samples = [0.0, Double.pi * 0.5, Double.pi, Double.pi * 1.5]
            guard samples.contains(where: {
                abs(configuration.discriminant(at: $0)) > residualTolerance
            }) else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    tolerance: tolerance,
                    message: "Sphere-torus intersection has a rank-deficient generator tangency over the complete angular domain."
                )
            }
            return try fullDomainIntersections(
                configuration: configuration,
                builder: builder,
                options: options,
                sphereSurface: sphereSurface,
                torusSurface: torusSurface,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }

        let intervalStates = elementaryIntervalStates(
            roots: roots,
            configuration: configuration,
            tolerance: tolerance
        )
        var results: [SurfaceSurfaceIntersection] = []
        for index in roots.indices where intervalStates[index] {
            let lower = roots[index]
            let upper = index + 1 < roots.count
                ? roots[index + 1]
                : roots[0] + 2.0 * Double.pi
            guard upper - lower > tolerance.angle else { continue }
            results.append(try intervalIntersection(
                interval: AngularInterval(lower: lower, upper: upper),
                configuration: configuration,
                builder: builder,
                options: options,
                sphereSurface: sphereSurface,
                torusSurface: torusSurface,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            ))
        }

        for index in roots.indices {
            let before = intervalStates[(index + roots.count - 1) % roots.count]
            let after = intervalStates[index]
            if before == false, after == false {
                let point = try intersectionPoint(
                    angle: roots[index],
                    branch: 1.0,
                    configuration: configuration,
                    tolerance: tolerance
                )
                results.append(try verifier.point(
                    point,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    tolerance: tolerance
                ))
            }
        }
        return results
    }

    private func fullDomainIntersections(
        configuration: Configuration,
        builder: SurfaceIntersectionSplineBuilder,
        options: SurfaceSurfaceIntersectionOptions,
        sphereSurface: Surface3D,
        torusSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let segmentCount = min(24, max(1, options.maximumSeedCount))
        let breaks = (0...segmentCount).map {
            Double($0) / Double(segmentCount)
        }
        return try [1.0, -1.0].map { branch in
            let derived = try builder.intersection(
                parameterRange: 0.0...1.0,
                initialBreaks: breaks,
                kind: .transverse,
                pointAt: { fraction in
                    try intersectionPoint(
                        angle: 2.0 * Double.pi * fraction,
                        branch: branch,
                        configuration: configuration,
                        tolerance: tolerance
                    )
                }
            )
            return try certifiedIntersection(
                derived,
                componentKind: branch < 0.0
                    ? .negativeFullBranch
                    : .positiveFullBranch,
                lowerAngle: 0.0,
                upperAngle: 2.0 * Double.pi,
                sphereSurface: sphereSurface,
                torusSurface: torusSurface,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }
    }

    private func intervalIntersection(
        interval: AngularInterval,
        configuration: Configuration,
        builder: SurfaceIntersectionSplineBuilder,
        options: SurfaceSurfaceIntersectionOptions,
        sphereSurface: Surface3D,
        torusSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let segmentCount = min(32, max(1, options.maximumSeedCount))
        let derived = try builder.intersection(
            parameterRange: 0.0...1.0,
            initialBreaks: (0...segmentCount).map {
                Double($0) / Double(segmentCount)
            },
            kind: .mixed,
            pointAt: { fraction in
                let midpoint = interval.lower
                    + (interval.upper - interval.lower) * 0.5
                let halfSpan = (interval.upper - interval.lower) * 0.5
                let phase = 2.0 * Double.pi * fraction
                let angle = midpoint - halfSpan * cos(phase)
                let branch = sin(phase) < 0.0 ? -1.0 : 1.0
                return try intersectionPoint(
                    angle: angle,
                    branch: branch,
                    configuration: configuration,
                    tolerance: tolerance
                )
            }
        )
        return try certifiedIntersection(
            derived,
            componentKind: .boundedAngularInterval,
            lowerAngle: interval.lower,
            upperAngle: interval.upper,
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
    }

    private func certifiedIntersection(
        _ derived: SurfaceSurfaceIntersection,
        componentKind: CertifiedSphereTorusIntersectionCurve.ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        sphereSurface: Surface3D,
        torusSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        guard case let .curve(derivedCurve) = derived else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A regular sphere-torus component did not produce a derived curve cache."
            )
        }
        let proceduralCurve = try CertifiedSphereTorusIntersectionCurve(
            sphereSurface: sphereSurface,
            torusSurface: torusSurface,
            componentKind: componentKind,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            tolerance: tolerance
        )
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            sphereTorusCurve: proceduralCurve,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        return .curve(try SurfaceSurfaceIntersectionCurve(
            truth: .analyticAnalytic(truth),
            derivedRepresentation: derivedCurve.derivedRepresentation,
            kind: derivedCurve.kind,
            firstSurfaceAnchor: derivedCurve.firstSurfaceAnchor,
            secondSurfaceAnchor: derivedCurve.secondSurfaceAnchor,
            tolerance: tolerance
        ))
    }

    private func intersectionPoint(
        angle: Double,
        branch: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        let coefficients = configuration.coefficients(at: angle)
        let amplitude = hypot(coefficients.cosine, coefficients.sine)
        let amplitudeTolerance = tolerance.distance * 1.0e-6
        guard amplitude > amplitudeTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: amplitude,
                tolerance: tolerance,
                message: "Sphere-torus tube-angle equation has a singular amplitude."
            )
        }
        let ratio = coefficients.value / amplitude
        let ratioTolerance = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        ) / max(amplitude * amplitude, 1.0)
        guard ratio >= -1.0 - ratioTolerance,
              ratio <= 1.0 + ratioTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: max(abs(ratio) - 1.0, 0.0),
                tolerance: tolerance,
                message: "Sphere-torus trace left its analytically classified angular domain."
            )
        }
        let phase = atan2(coefficients.sine, coefficients.cosine)
        let discriminant = amplitude * amplitude
            - coefficients.value * coefficients.value
        let offset = atan2(
            sqrt(max(discriminant, 0.0)),
            coefficients.value
        )
        let tubeAngle = phase + branch * offset
        return try configuration.torus.surface.point(
            u: normalizedAngle(angle),
            v: normalizedAngle(tubeAngle),
            tolerance: tolerance
        )
    }

    private func makeConfiguration(
        sphere: CanonicalAnalyticSurface.Sphere,
        torus: Torus,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        let outerRadius = torus.majorRadius + torus.minorRadius
        let zeroPoint = try torus.surface.point(u: 0.0, v: 0.0, tolerance: tolerance)
        let quarterPoint = try torus.surface.point(
            u: Double.pi * 0.5,
            v: 0.0,
            tolerance: tolerance
        )
        let zeroRadial = try ((zeroPoint - torus.center) / outerRadius).normalized(
            tolerance: tolerance.distance
        )
        let quarterRadial = try ((quarterPoint - torus.center) / outerRadius).normalized(
            tolerance: tolerance.distance
        )
        let centerOffset = torus.center - sphere.center
        let axialCoefficient = centerOffset.dot(torus.axis)

        func discriminant(at angle: Double) -> Double {
            let radial = zeroRadial * cos(angle) + quarterRadial * sin(angle)
            let radialOffset = centerOffset.dot(radial)
            let cosine = torus.majorRadius + radialOffset
            let baseSquared = centerOffset.dot(centerOffset)
                + torus.majorRadius * torus.majorRadius
                + 2.0 * torus.majorRadius * radialOffset
            let value = (
                sphere.radius * sphere.radius
                    - baseSquared
                    - torus.minorRadius * torus.minorRadius
            ) / (2.0 * torus.minorRadius)
            return cosine * cosine + axialCoefficient * axialCoefficient - value * value
        }

        let zero = discriminant(at: 0.0)
        let half = discriminant(at: Double.pi)
        let quarter = discriminant(at: Double.pi * 0.5)
        let threeQuarter = discriminant(at: Double.pi * 1.5)
        let diagonal = discriminant(at: Double.pi * 0.25)
        let constantPlusDouble = (zero + half) * 0.5
        let constantMinusDouble = (quarter + threeQuarter) * 0.5
        let constant = (constantPlusDouble + constantMinusDouble) * 0.5
        let cosineDouble = (constantPlusDouble - constantMinusDouble) * 0.5
        let cosine = (zero - half) * 0.5
        let sine = (quarter - threeQuarter) * 0.5
        let sineDouble = diagonal
            - constant
            - (cosine + sine) / sqrt(2.0)
        return Configuration(
            sphere: sphere,
            torus: torus,
            zeroRadial: zeroRadial,
            quarterRadial: quarterRadial,
            centerOffset: centerOffset,
            axialCoefficient: axialCoefficient,
            discriminantPolynomial: TrigonometricPolynomial(
                constant: constant,
                cosine: cosine,
                sine: sine,
                cosineDouble: cosineDouble,
                sineDouble: sineDouble
            )
        )
    }

    private func boundaryAngles(
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let polynomial = configuration.discriminantPolynomial
        let residualTolerance = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let normalizedResidual = max(
            Double.ulpOfOne * 1024.0,
            residualTolerance / polynomial.coefficientScale
        )
        let refinementResidualTolerance = max(
            Double.ulpOfOne * polynomial.coefficientScale * 128.0,
            residualTolerance * 1.0e-8
        )
        let solver = try RealPolynomialRootSolver(
            rootTolerance: max(tolerance.angle * 0.25, Double.ulpOfOne * 1024.0),
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
                message: "Sphere-torus boundary classification exceeded its root limit."
            )
        }
        var values = tangentRoots.map { root in
            normalizedAngle(2.0 * atan(root))
        }
        if abs(polynomial.value(at: Double.pi)) <= residualTolerance {
            values.append(Double.pi)
        }
        values = values.map { value in
            refinedAngle(
                value,
                polynomial: polynomial,
                maximumIterations: options.maximumIterations,
                residualTolerance: refinementResidualTolerance,
                tolerance: tolerance
            )
        }.filter { value in
            abs(polynomial.value(at: value)) <= residualTolerance * 16.0
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
        for _ in 0..<maximumIterations {
            let value = polynomial.value(at: angle)
            if abs(value) <= residualTolerance { break }
            let derivative = polynomial.derivative(at: angle)
            let derivativeThreshold = polynomial.coefficientScale * tolerance.angle
            guard abs(derivative) > derivativeThreshold else { break }
            let step = value / derivative
            guard step.isFinite, abs(step) <= Double.pi * 0.5 else { break }
            angle = normalizedAngle(angle - step)
            let angularRoundoff = Double.ulpOfOne * max(abs(angle), 1.0) * 128.0
            if abs(step) <= angularRoundoff { break }
        }
        return angle
    }

    private func elementaryIntervalStates(
        roots: [Double],
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> [Bool] {
        roots.indices.map { index in
            let lower = roots[index]
            let upper = index + 1 < roots.count
                ? roots[index + 1]
                : roots[0] + 2.0 * Double.pi
            return isAllowed(
                angle: lower + (upper - lower) * 0.5,
                configuration: configuration,
                tolerance: tolerance
            )
        }
    }

    private func isAllowed(
        angle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Bool {
        configuration.discriminant(at: angle) >= -classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
    }

    private func classificationTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        let scale = max(
            configuration.sphere.radius,
            configuration.torus.majorRadius + configuration.torus.minorRadius,
            configuration.centerOffset.length,
            1.0
        )
        let algebraicScale = max(
            configuration.discriminantPolynomial.coefficientScale,
            scale * scale
        )
        return max(
            Double.ulpOfOne * algebraicScale * 4096.0,
            tolerance.distance * (2.0 * scale + tolerance.distance) * 1.0e-6
        )
    }

    private func rejectSpherePoleContact(
        sphere: CanonicalAnalyticSurface.Sphere,
        torus: Torus,
        tolerance: ModelingTolerance
    ) throws {
        for sign in [-1.0, 1.0] {
            let pole = sphere.center + Vector3D.unitZ * (sign * sphere.radius)
            do {
                let projection = try torus.surface.parameterProjection(
                    of: pole,
                    tolerance: tolerance
                )
                if projection.residual <= tolerance.distance {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularGeometry,
                        residual: projection.residual,
                        tolerance: tolerance,
                        message: "Sphere-torus intersection passes through a singular spherical parameter pole."
                    )
                }
            } catch let error as KernelError where error.code == .intersectionFailure {
                continue
            }
        }
    }

    private func canonicalTorus(
        _ torus: CanonicalAnalyticSurface.Torus,
        tolerance: ModelingTolerance
    ) throws -> Torus {
        var axis = try torus.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) { axis = -axis }
        return Torus(
            center: torus.center,
            axis: axis,
            majorRadius: torus.majorRadius,
            minorRadius: torus.minorRadius
        )
    }

    private func angularDistance(_ first: Double, _ second: Double) -> Double {
        let difference = abs(first - second)
        return min(difference, 2.0 * Double.pi - difference)
    }

    private func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        let period = 2.0 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }
}
