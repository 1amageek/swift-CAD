import Foundation
import CADCore

struct GeneralConeConeSurfaceIntersector {
    private struct Cone {
        let apex: Point3D
        let axis: Vector3D
        let halfAngle: Double

        var surface: Surface3D {
            .analytic(.cone(
                apex: apex,
                axis: axis,
                halfAngle: halfAngle
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

        var derivativePolynomial: TrigonometricPolynomial {
            TrigonometricPolynomial(
                constant: 0.0,
                cosine: sine,
                sine: -cosine,
                cosineDouble: 2.0 * sineDouble,
                sineDouble: -2.0 * cosineDouble
            )
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
        let reference: Cone
        let parameterized: Cone
        let baseOffset: Vector3D
        let referenceMetricScale: Double
        let constantTerm: Double
        let quadraticPolynomial: TrigonometricPolynomial
        let discriminantPolynomial: TrigonometricPolynomial

        func direction(at angle: Double, tolerance: ModelingTolerance) throws -> Vector3D {
            try parameterized.surface.point(
                u: normalizedAngle(angle),
                v: 1.0,
                tolerance: tolerance
            ) - parameterized.apex
        }

        func metric(_ first: Vector3D, _ second: Vector3D) -> Double {
            first.dot(second)
                - referenceMetricScale
                    * first.dot(reference.axis)
                    * second.dot(reference.axis)
        }

        func quadratic(at angle: Double) -> Double {
            quadraticPolynomial.value(at: angle)
        }

        func halfLinear(
            at angle: Double,
            tolerance: ModelingTolerance
        ) throws -> Double {
            metric(baseOffset, try direction(at: angle, tolerance: tolerance))
        }

        func discriminant(at angle: Double) -> Double {
            discriminantPolynomial.value(at: angle)
        }

        private func normalizedAngle(_ angle: Double) -> Double {
            let period = 2.0 * Double.pi
            let remainder = angle.truncatingRemainder(dividingBy: period)
            return remainder >= 0.0 ? remainder : remainder + period
        }
    }

    private struct AngularInterval {
        let lower: Double
        let upper: Double
    }

    private struct ClassifiedConfiguration {
        let configuration: Configuration
        let minimumDiscriminant: Double
        let maximumDiscriminant: Double
    }

    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        first: CanonicalAnalyticSurface.Cone,
        second: CanonicalAnalyticSurface.Cone,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let cones = try [
            canonicalCone(first, tolerance: tolerance),
            canonicalCone(second, tolerance: tolerance),
        ].sorted { coneKey($0).lexicographicallyPrecedes(coneKey($1)) }
        let configurations = try [
            makeConfiguration(
                reference: cones[0],
                parameterized: cones[1],
                tolerance: tolerance
            ),
            makeConfiguration(
                reference: cones[1],
                parameterized: cones[0],
                tolerance: tolerance
            ),
        ]
        try rejectApexContact(configurations[0], tolerance: tolerance)

        var fullDomainConfiguration: ClassifiedConfiguration?
        var partialDomainConfiguration: ClassifiedConfiguration?
        var disjointConfigurationCount = 0
        var partialResidual: Double?
        var singularResidual: Double?
        for configuration in configurations {
            let discriminantTolerance = classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            )
            let minimumDiscriminant = try extremum(
                of: configuration.discriminantPolynomial,
                maximum: false,
                residualTolerance: discriminantTolerance,
                options: options,
                tolerance: tolerance
            )
            let maximumDiscriminant = try extremum(
                of: configuration.discriminantPolynomial,
                maximum: true,
                residualTolerance: discriminantTolerance,
                options: options,
                tolerance: tolerance
            )
            if maximumDiscriminant < -discriminantTolerance {
                disjointConfigurationCount += 1
                continue
            }
            let quadraticTolerance = max(
                tolerance.angle * 8.0,
                Double.ulpOfOne
                    * configuration.quadraticPolynomial.coefficientScale
                    * 2_048.0
            )
            let minimumQuadratic = try extremum(
                of: configuration.quadraticPolynomial,
                maximum: false,
                residualTolerance: quadraticTolerance,
                options: options,
                tolerance: tolerance
            )
            let maximumQuadratic = try extremum(
                of: configuration.quadraticPolynomial,
                maximum: true,
                residualTolerance: quadraticTolerance,
                options: options,
                tolerance: tolerance
            )
            guard minimumQuadratic > quadraticTolerance
                    || maximumQuadratic < -quadraticTolerance else {
                singularResidual = min(
                    singularResidual ?? .infinity,
                    min(abs(minimumQuadratic), abs(maximumQuadratic))
                )
                continue
            }
            let classified = ClassifiedConfiguration(
                configuration: configuration,
                minimumDiscriminant: minimumDiscriminant,
                maximumDiscriminant: maximumDiscriminant
            )
            if minimumDiscriminant <= discriminantTolerance {
                partialResidual = min(
                    partialResidual ?? .infinity,
                    abs(minimumDiscriminant)
                )
                if partialDomainConfiguration == nil {
                    partialDomainConfiguration = classified
                }
                continue
            }
            fullDomainConfiguration = classified
            break
        }
        let selectedConfiguration = fullDomainConfiguration
            ?? partialDomainConfiguration
        guard let selectedConfiguration else {
            if disjointConfigurationCount == configurations.count {
                return []
            }
            if partialResidual == nil, let singularResidual {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: singularResidual,
                    tolerance: tolerance,
                    message: "General cone-cone intersection contains a ruling asymptotic to the other cone."
                )
            }
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: partialResidual,
                tolerance: tolerance,
                message: "General cone-cone tracing exhausted its branch-completeness budget before certifying the full intersection."
            )
        }

        let configuration = selectedConfiguration.configuration
        let builder = SurfaceIntersectionSplineBuilder(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )
        let discriminantTolerance = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        if selectedConfiguration.minimumDiscriminant < -discriminantTolerance,
           selectedConfiguration.maximumDiscriminant <= discriminantTolerance {
            return try isolatedTangencies(
                configuration: configuration,
                maximumDiscriminant: selectedConfiguration.maximumDiscriminant,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                options: options,
                tolerance: tolerance
            )
        }
        let roots = try boundaryAngles(
            configuration: configuration,
            options: options,
            tolerance: tolerance
        )
        if roots.isEmpty {
            guard selectedConfiguration.maximumDiscriminant >= -classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            ) else {
                return []
            }
            return try fullDomainIntersections(
                configuration: configuration,
                maximumDiscriminant: selectedConfiguration.maximumDiscriminant,
                builder: builder,
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

    private func isolatedTangencies(
        configuration: Configuration,
        maximumDiscriminant: Double,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let discriminantTolerance = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let stationaryAngles = try roots(
            of: configuration.discriminantPolynomial.derivativePolynomial,
            options: options,
            residualTolerance: discriminantTolerance,
            tolerance: tolerance
        )
        let contactAngles = stationaryAngles.filter { angle in
            abs(configuration.discriminant(at: angle) - maximumDiscriminant)
                <= discriminantTolerance * 16.0
        }
        var points: [Point3D] = []
        for angle in contactAngles {
            let point = try intersectionPoint(
                angle: angle,
                branch: 1.0,
                configuration: configuration,
                tolerance: tolerance
            )
            if points.contains(where: {
                $0.isApproximatelyEqual(to: point, tolerance: tolerance.distance)
            }) == false {
                points.append(point)
            }
        }
        guard points.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: abs(maximumDiscriminant),
                tolerance: tolerance,
                message: "General cone-cone isolated-contact classification found no stationary contact point."
            )
        }
        return try points.map { point in
            try verifier.point(
                point,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }
    }

    private func fullDomainIntersections(
        configuration: Configuration,
        maximumDiscriminant: Double,
        builder: SurfaceIntersectionSplineBuilder,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let discriminantTolerance = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        let branches: [Double]
        let kind: CurveSurfaceIntersectionKind
        if maximumDiscriminant <= discriminantTolerance {
            branches = [1.0]
            kind = .tangent
        } else {
            branches = [1.0, -1.0]
            kind = .transverse
        }
        let breaks = (0...16).map { Double($0) * Double.pi / 8.0 }
        return try branches.map { branch in
            try builder.intersection(
                parameterRange: 0.0...(2.0 * Double.pi),
                initialBreaks: breaks,
                kind: kind,
                pointAt: { angle in
                    try intersectionPoint(
                        angle: angle,
                        branch: branch,
                        configuration: configuration,
                        tolerance: tolerance
                    )
                }
            )
        }
    }

    private func intervalIntersection(
        interval: AngularInterval,
        configuration: Configuration,
        builder: SurfaceIntersectionSplineBuilder,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        try builder.intersection(
            parameterRange: 0.0...2.0,
            initialBreaks: (0...8).map { Double($0) * 0.25 },
            kind: .mixed,
            pointAt: { parameter in
                let angle: Double
                let branch: Double
                if parameter <= 1.0 {
                    let sine = sin(Double.pi * parameter * 0.5)
                    angle = interval.lower
                        + (interval.upper - interval.lower) * sine * sine
                    branch = 1.0
                } else {
                    let local = parameter - 1.0
                    let sine = sin(Double.pi * local * 0.5)
                    angle = interval.upper
                        - (interval.upper - interval.lower) * sine * sine
                    branch = -1.0
                }
                return try intersectionPoint(
                    angle: angle,
                    branch: branch,
                    configuration: configuration,
                    tolerance: tolerance
                )
            }
        )
    }

    private func intersectionPoint(
        angle: Double,
        branch: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        let discriminant = configuration.discriminant(at: angle)
        let discriminantTolerance = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        guard discriminant >= -discriminantTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: sqrt(-discriminant),
                tolerance: tolerance,
                message: "General cone-cone trace left its analytically classified domain."
            )
        }
        let quadratic = configuration.quadratic(at: angle)
        let halfLinear = try configuration.halfLinear(
            at: angle,
            tolerance: tolerance
        )
        let parameter = (
            -halfLinear + branch * sqrt(max(0.0, discriminant))
        ) / quadratic
        guard parameter.isFinite, abs(parameter) > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: abs(parameter),
                tolerance: tolerance,
                message: "General cone-cone intersection passes through a singular cone apex parameter."
            )
        }
        let point = try configuration.parameterized.surface.point(
            u: normalizedAngle(angle),
            v: parameter,
            tolerance: tolerance
        )
        let referenceDistance = (point - configuration.reference.apex).length
        guard referenceDistance > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: referenceDistance,
                tolerance: tolerance,
                message: "General cone-cone intersection passes through a singular cone apex parameter."
            )
        }
        return point
    }

    private func makeConfiguration(
        reference: Cone,
        parameterized: Cone,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        let baseOffset = parameterized.apex - reference.apex
        let metricScale = 1.0 / pow(cos(reference.halfAngle), 2.0)

        func metric(_ first: Vector3D, _ second: Vector3D) -> Double {
            first.dot(second)
                - metricScale
                    * first.dot(reference.axis)
                    * second.dot(reference.axis)
        }

        func direction(at angle: Double) throws -> Vector3D {
            try parameterized.surface.point(
                u: normalizedAngle(angle),
                v: 1.0,
                tolerance: tolerance
            ) - parameterized.apex
        }

        let constant = metric(baseOffset, baseOffset)
        let quadratic = try trigonometricPolynomial { angle in
            let generator = try direction(at: angle)
            return metric(generator, generator)
        }
        let discriminant = try trigonometricPolynomial { angle in
            let generator = try direction(at: angle)
            let halfLinear = metric(baseOffset, generator)
            return halfLinear * halfLinear
                - metric(generator, generator) * constant
        }
        return Configuration(
            reference: reference,
            parameterized: parameterized,
            baseOffset: baseOffset,
            referenceMetricScale: metricScale,
            constantTerm: constant,
            quadraticPolynomial: quadratic,
            discriminantPolynomial: discriminant
        )
    }

    private func trigonometricPolynomial(
        valueAt: (Double) throws -> Double
    ) rethrows -> TrigonometricPolynomial {
        let zero = try valueAt(0.0)
        let half = try valueAt(Double.pi)
        let quarter = try valueAt(Double.pi * 0.5)
        let threeQuarter = try valueAt(Double.pi * 1.5)
        let diagonal = try valueAt(Double.pi * 0.25)
        let constantPlusDouble = (zero + half) * 0.5
        let constantMinusDouble = (quarter + threeQuarter) * 0.5
        let constant = (constantPlusDouble + constantMinusDouble) * 0.5
        let cosineDouble = (constantPlusDouble - constantMinusDouble) * 0.5
        let cosine = (zero - half) * 0.5
        let sine = (quarter - threeQuarter) * 0.5
        let sineDouble = diagonal
            - constant
            - (cosine + sine) / sqrt(2.0)
        return TrigonometricPolynomial(
            constant: constant,
            cosine: cosine,
            sine: sine,
            cosineDouble: cosineDouble,
            sineDouble: sineDouble
        )
    }

    private func extremum(
        of polynomial: TrigonometricPolynomial,
        maximum: Bool,
        residualTolerance: Double,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let stationaryAngles = try roots(
            of: polynomial.derivativePolynomial,
            options: options,
            residualTolerance: residualTolerance,
            tolerance: tolerance
        )
        let values = ([0.0] + stationaryAngles).map(polynomial.value)
        if maximum {
            return values.max() ?? polynomial.value(at: 0.0)
        }
        return values.min() ?? polynomial.value(at: 0.0)
    }

    private func boundaryAngles(
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        try roots(
            of: configuration.discriminantPolynomial,
            options: options,
            residualTolerance: classificationTolerance(
                configuration: configuration,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
    }

    private func roots(
        of polynomial: TrigonometricPolynomial,
        options: SurfaceSurfaceIntersectionOptions,
        residualTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let normalizedResidual = max(
            Double.ulpOfOne * 1_024.0,
            residualTolerance / polynomial.coefficientScale
        )
        let solver = try RealPolynomialRootSolver(
            rootTolerance: max(
                tolerance.angle * 0.25,
                Double.ulpOfOne * 1_024.0
            ),
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
                message: "General cone-cone classification exceeded its root limit."
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
                residualTolerance: residualTolerance,
                tolerance: tolerance
            )
        }.filter { value in
            abs(polynomial.value(at: value)) <= residualTolerance * 16.0
        }.sorted()

        var result: [Double] = []
        for value in values where
            result.last.map({ angularDistance($0, value) <= tolerance.angle }) != true {
            result.append(value)
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
            if abs(value) <= residualTolerance {
                break
            }
            let derivative = polynomial.derivative(at: angle)
            let derivativeThreshold = polynomial.coefficientScale * tolerance.angle
            guard abs(derivative) > derivativeThreshold else { break }
            let step = value / derivative
            guard step.isFinite, abs(step) <= Double.pi * 0.5 else { break }
            angle = normalizedAngle(angle - step)
            if abs(step) <= tolerance.angle * 0.25 {
                break
            }
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

    private func rejectApexContact(
        _ configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws {
        let scale = max(configuration.baseOffset.length, 1.0)
        let algebraicTolerance = max(
            Double.ulpOfOne * scale * scale * 4_096.0,
            tolerance.distance * (2.0 * scale + tolerance.distance)
        )
        let referenceAtParameterizedApex = abs(configuration.constantTerm)
        let reverseMetricScale = 1.0
            / pow(cos(configuration.parameterized.halfAngle), 2.0)
        let reverseOffset = configuration.reference.apex
            - configuration.parameterized.apex
        let parameterizedAtReferenceApex = abs(
            reverseOffset.dot(reverseOffset)
                - reverseMetricScale
                    * pow(reverseOffset.dot(configuration.parameterized.axis), 2.0)
        )
        let residual = min(
            referenceAtParameterizedApex,
            parameterizedAtReferenceApex
        )
        guard residual > algebraicTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: sqrt(max(residual, 0.0)),
                tolerance: tolerance,
                message: "General cone-cone intersection passes through a singular cone apex parameter."
            )
        }
    }

    private func classificationTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        let scale = max(configuration.baseOffset.length, 1.0)
        let algebraicScale = max(
            configuration.discriminantPolynomial.coefficientScale,
            scale * scale
        )
        return max(
            Double.ulpOfOne * algebraicScale * 4_096.0,
            tolerance.distance * (2.0 * scale + tolerance.distance) * 1.0e-6
        )
    }

    private func canonicalCone(
        _ cone: CanonicalAnalyticSurface.Cone,
        tolerance: ModelingTolerance
    ) throws -> Cone {
        var axis = try cone.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) {
            axis = -axis
        }
        return Cone(
            apex: cone.apex,
            axis: axis,
            halfAngle: cone.halfAngle
        )
    }

    private func coneKey(_ cone: Cone) -> [Double] {
        [
            cone.halfAngle,
            cone.apex.x,
            cone.apex.y,
            cone.apex.z,
            cone.axis.x,
            cone.axis.y,
            cone.axis.z,
        ]
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
