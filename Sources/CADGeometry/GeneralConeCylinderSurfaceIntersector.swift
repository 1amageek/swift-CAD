import Foundation
import CADCore

struct GeneralConeCylinderSurfaceIntersector {
    private struct Cone {
        let apex: Point3D
        let axis: Vector3D
        let halfAngle: Double

        var surface: Surface3D {
            .analytic(.cone(apex: apex, axis: axis, halfAngle: halfAngle))
        }
    }

    private struct Cylinder {
        let origin: Point3D
        let axis: Vector3D
        let radius: Double

        var surface: Surface3D {
            .analytic(.cylinder(origin: origin, axis: axis, radius: radius))
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
        let cone: Cone
        let cylinder: Cylinder
        let cylinderRadialU: Vector3D
        let cylinderRadialV: Vector3D
        let coneMetricScale: Double
        let generatorQuadratic: Double
        let discriminantPolynomial: TrigonometricPolynomial

        func cylinderBaseOffset(at angle: Double) -> Vector3D {
            cylinder.origin - cone.apex
                + cylinderRadialU * cos(angle)
                + cylinderRadialV * sin(angle)
        }

        func coneMetric(_ first: Vector3D, _ second: Vector3D) -> Double {
            first.dot(second)
                - coneMetricScale * first.dot(cone.axis) * second.dot(cone.axis)
        }

        func halfLinear(at angle: Double) -> Double {
            coneMetric(cylinderBaseOffset(at: angle), cylinder.axis)
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
    private let rulingParallelIntersector =
        ConeCylinderRulingParallelIntersector()

    func intersections(
        cone: CanonicalAnalyticSurface.Cone,
        cylinder: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let coneSurface: Surface3D
        let cylinderSurface: Surface3D
        if case .cone = CanonicalAnalyticSurface(firstSurface) {
            coneSurface = firstSurface
            cylinderSurface = secondSurface
        } else {
            coneSurface = secondSurface
            cylinderSurface = firstSurface
        }
        let canonicalCone = try canonicalCone(cone, tolerance: tolerance)
        let canonicalCylinder = try canonicalCylinder(cylinder, tolerance: tolerance)
        if let intersections = try rulingParallelIntersector
            .intersectionsIfApplicable(
                coneSurface: coneSurface,
                cylinderSurface: cylinderSurface,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                options: options,
                tolerance: tolerance
            ) {
            return intersections
        }
        let configuration = try makeConfiguration(
            cone: canonicalCone,
            cylinder: canonicalCylinder,
            tolerance: tolerance
        )
        let apexAngle = try CertifiedConeCylinderIntersectionCurve
            .apexContactAngle(
                coneSurface: coneSurface,
                cylinderSurface: cylinderSurface,
                tolerance: tolerance
            )
        var roots = try boundaryAngles(
            configuration: configuration,
            options: options,
            tolerance: tolerance
        )
        if let apexAngle,
           roots.contains(where: {
               angularDistance($0, apexAngle) <= tolerance.angle
           }) == false {
            roots.append(apexAngle)
            roots.sort()
        }
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
            return try fullDomainIntersections(
                configuration: configuration,
                builder: builder,
                options: options,
                coneSurface: coneSurface,
                cylinderSurface: cylinderSurface,
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
                let interval = AngularInterval(lower: lower, upper: upper)
                if let apexAngle,
                   angularDistance(lower, apexAngle) <= tolerance.angle
                    || angularDistance(upper, apexAngle) <= tolerance.angle {
                    results.append(try apexNodeIntervalIntersection(
                        interval: interval,
                        apexAngle: apexAngle,
                        coneSurface: coneSurface,
                        cylinderSurface: cylinderSurface,
                        firstSurface: firstSurface,
                        secondSurface: secondSurface,
                        tolerance: tolerance
                    ))
                } else {
                    results.append(try intervalIntersection(
                        interval: interval,
                        configuration: configuration,
                        builder: builder,
                        coneSurface: coneSurface,
                        cylinderSurface: cylinderSurface,
                        firstSurface: firstSurface,
                        secondSurface: secondSurface,
                        tolerance: tolerance
                    ))
                }
        }

        for index in roots.indices {
            let before = intervalStates[(index + roots.count - 1) % roots.count]
            let after = intervalStates[index]
            if before == false, after == false {
                let point = if let apexAngle,
                    angularDistance(roots[index], apexAngle) <= tolerance.angle {
                    canonicalCone.apex
                } else {
                    try intersectionPoint(
                        angle: roots[index],
                        branch: 1.0,
                        configuration: configuration,
                        tolerance: tolerance
                    )
                }
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
        coneSurface: Surface3D,
        cylinderSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let maximumDiscriminant = try extremum(
            of: configuration.discriminantPolynomial,
            maximum: true,
            options: options,
            tolerance: tolerance
        )
        let discriminantTolerance = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        guard maximumDiscriminant > discriminantTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: maximumDiscriminant,
                tolerance: tolerance,
                message: "A cone-cylinder full domain requires a certified positive discriminant margin."
            )
        }
        let branches = [1.0, -1.0]
        let kind = CurveSurfaceIntersectionKind.transverse
        let breaks = (0...16).map { Double($0) / 16.0 }
        return try branches.map { branch in
            let derived = try builder.intersection(
                parameterRange: 0.0...1.0,
                initialBreaks: breaks,
                kind: kind,
                pointAt: { fraction in
                    try intersectionPoint(
                        angle: 2.0 * Double.pi * fraction,
                        branch: branch,
                        configuration: configuration,
                        tolerance: tolerance
                    )
                }
            )
            let componentKind:
                CertifiedConeCylinderIntersectionCurve.ComponentKind =
                    branch < 0.0
                        ? .negativeFullBranch
                        : .positiveFullBranch
            return try certifiedIntersection(
                derived,
                componentKind: componentKind,
                lowerAngle: 0.0,
                upperAngle: 2.0 * Double.pi,
                coneSurface: coneSurface,
                cylinderSurface: cylinderSurface,
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
        coneSurface: Surface3D,
        cylinderSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let derived = try builder.intersection(
            parameterRange: 0.0...1.0,
            initialBreaks: (0...8).map { Double($0) / 8.0 },
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
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
    }

    private func apexNodeIntervalIntersection(
        interval: AngularInterval,
        apexAngle: Double,
        coneSurface: Surface3D,
        cylinderSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let componentKind: CertifiedConeCylinderIntersectionCurve.ComponentKind
        if angularDistance(interval.lower, apexAngle) <= tolerance.angle {
            componentKind = .apexLowerNodeInterval
        } else {
            componentKind = .apexUpperNodeInterval
        }
        let proceduralCurve = try CertifiedConeCylinderIntersectionCurve(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            componentKind: componentKind,
            lowerAngle: interval.lower,
            upperAngle: interval.upper,
            tolerance: tolerance
        )
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            coneCylinderCurve: proceduralCurve,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        let point = try truth.point(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        let firstParameter = try truth.internalParameter(
            for: .first,
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        let secondParameter = try truth.internalParameter(
            for: .second,
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        let firstParameterCurve = truth.firstSurfaceParameterCurve
        let secondParameterCurve = truth.secondSurfaceParameterCurve
        return .curve(try SurfaceSurfaceIntersectionCurve(
            truth: .analyticAnalytic(truth),
            derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
                curve: truth.curve,
                firstSurfaceParameterCurve: firstParameterCurve,
                secondSurfaceParameterCurve: secondParameterCurve,
                maximumResidualUpperBound: 0.0,
                tolerance: tolerance
            ),
            kind: .mixed,
            firstSurfaceAnchor: try SurfaceParameterProjection(
                u: firstParameter.u,
                v: firstParameter.v,
                point: point,
                residual: 0.0
            ),
            secondSurfaceAnchor: try SurfaceParameterProjection(
                u: secondParameter.u,
                v: secondParameter.v,
                point: point,
                residual: 0.0
            ),
            tolerance: tolerance
        ))
    }

    private func certifiedIntersection(
        _ derived: SurfaceSurfaceIntersection,
        componentKind: CertifiedConeCylinderIntersectionCurve.ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        coneSurface: Surface3D,
        cylinderSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        guard case let .curve(derivedCurve) = derived else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A regular cone-cylinder component did not produce a derived curve cache."
            )
        }
        let proceduralCurve = try CertifiedConeCylinderIntersectionCurve(
            coneSurface: coneSurface,
            cylinderSurface: cylinderSurface,
            componentKind: componentKind,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            tolerance: tolerance
        )
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            coneCylinderCurve: proceduralCurve,
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
        let rawDiscriminant = configuration.discriminant(at: angle)
        let discriminantTolerance = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        guard rawDiscriminant >= -discriminantTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: sqrt(-rawDiscriminant),
                tolerance: tolerance,
                message: "Cone-cylinder trace left its analytically classified domain."
            )
        }
        let height = (
            -configuration.halfLinear(at: angle)
                + branch * sqrt(max(0.0, rawDiscriminant))
        ) / configuration.generatorQuadratic
        let point = try configuration.cylinder.surface.point(
            u: normalizedAngle(angle),
            v: height,
            tolerance: tolerance
        )
        let apexResidual = (point - configuration.cone.apex).length
        guard apexResidual > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: apexResidual,
                tolerance: tolerance,
                message: "Cone-cylinder intersection passes through the cone's singular apex parameter."
            )
        }
        return point
    }

    private func makeConfiguration(
        cone: Cone,
        cylinder: Cylinder,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        let coneMetricScale = 1.0 / pow(cos(cone.halfAngle), 2.0)
        let generatorQuadratic = 1.0
            - coneMetricScale * pow(cylinder.axis.dot(cone.axis), 2.0)
        let singularityThreshold = max(
            tolerance.angle * 8.0,
            Double.ulpOfOne * 512.0
        )
        guard abs(generatorQuadratic) > singularityThreshold else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: abs(generatorQuadratic),
                tolerance: tolerance,
                message: "Cone-cylinder generator is parallel to a cone ruling."
            )
        }
        let zeroPoint = try cylinder.surface.point(
            u: 0.0,
            v: 0.0,
            tolerance: tolerance
        )
        let quarterPoint = try cylinder.surface.point(
            u: Double.pi * 0.5,
            v: 0.0,
            tolerance: tolerance
        )
        let radialU = zeroPoint - cylinder.origin
        let radialV = quarterPoint - cylinder.origin
        let baseOffset = cylinder.origin - cone.apex

        func metric(_ first: Vector3D, _ second: Vector3D) -> Double {
            first.dot(second)
                - coneMetricScale * first.dot(cone.axis) * second.dot(cone.axis)
        }

        func discriminant(at angle: Double) -> Double {
            let offset = baseOffset
                + radialU * cos(angle)
                + radialV * sin(angle)
            let halfLinear = metric(offset, cylinder.axis)
            return halfLinear * halfLinear
                - generatorQuadratic * metric(offset, offset)
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
            cone: cone,
            cylinder: cylinder,
            cylinderRadialU: radialU,
            cylinderRadialV: radialV,
            coneMetricScale: coneMetricScale,
            generatorQuadratic: generatorQuadratic,
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
            Double.ulpOfOne * 1024.0,
            residualTolerance / polynomial.coefficientScale
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
                message: "Cone-cylinder boundary classification exceeded its root limit."
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

    private func extremum(
        of polynomial: TrigonometricPolynomial,
        maximum: Bool,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let residualTolerance = max(
            polynomial.coefficientScale * Double.ulpOfOne * 1024.0,
            tolerance.distance * tolerance.distance * 1.0e-6
        )
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
            (configuration.cylinder.origin - configuration.cone.apex).length,
            configuration.cylinder.radius,
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

    private func canonicalCone(
        _ cone: CanonicalAnalyticSurface.Cone,
        tolerance: ModelingTolerance
    ) throws -> Cone {
        var axis = try cone.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) {
            axis = -axis
        }
        return Cone(apex: cone.apex, axis: axis, halfAngle: cone.halfAngle)
    }

    private func canonicalCylinder(
        _ cylinder: CanonicalAnalyticSurface.Cylinder,
        tolerance: ModelingTolerance
    ) throws -> Cylinder {
        var axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) {
            axis = -axis
        }
        let originVector = cylinder.origin - .origin
        let origin = cylinder.origin + axis * -originVector.dot(axis)
        return Cylinder(origin: origin, axis: axis, radius: cylinder.radius)
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
