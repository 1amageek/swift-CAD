import Foundation
import CADCore

struct GeneralCylinderCylinderSurfaceIntersector {
    private struct Cylinder {
        let origin: Point3D
        let axis: Vector3D
        let radius: Double

        var surface: Surface3D {
            .analytic(.cylinder(origin: origin, axis: axis, radius: radius))
        }
    }

    private struct Configuration {
        let first: Cylinder
        let second: Cylinder
        let normal: Vector3D
        let projectedAxis: Vector3D
        let projectedAxisSquaredLength: Double
        let harmonicCenter: Double
        let harmonicCosine: Double
        let harmonicSine: Double

        var harmonicAmplitude: Double {
            hypot(harmonicCosine, harmonicSine)
        }

        func signedGeneratorDistance(at angle: Double) -> Double {
            harmonicCenter
                + harmonicCosine * cos(angle)
                + harmonicSine * sin(angle)
        }
    }

    private struct AngularInterval {
        let lower: Double
        let upper: Double
    }

    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        first: CanonicalAnalyticSurface.Cylinder,
        second: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let firstAxis = try first.axis.normalized(tolerance: tolerance.distance)
        let secondAxis = try second.axis.normalized(tolerance: tolerance.distance)
        let axisCross = firstAxis.cross(secondAxis)
        guard axisCross.length > tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "General cylinder intersection requires non-parallel axes."
            )
        }

        let axisDistance = abs((second.origin - first.origin).dot(
            try axisCross.normalized(tolerance: tolerance.angle)
        ))
        if abs(first.radius - second.radius) <= tolerance.distance,
           axisDistance <= tolerance.distance {
            return try IntersectingEqualRadiusCylinderSurfaceIntersector().intersections(
                first: first,
                second: second,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }

        let cylinders = try [
            canonicalCylinder(first, tolerance: tolerance),
            canonicalCylinder(second, tolerance: tolerance),
        ].sorted(by: precedes)
        let configuration = try makeConfiguration(
            first: cylinders[0],
            second: cylinders[1],
            tolerance: tolerance
        )
        let roots = boundaryAngles(configuration: configuration, tolerance: tolerance)
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

    private func fullDomainIntersections(
        configuration: Configuration,
        builder: SurfaceIntersectionSplineBuilder,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let maximumRadicand = maximumRadicand(configuration: configuration)
        let radicandTolerance = squaredDistanceTolerance(
            radius: configuration.second.radius,
            tolerance: tolerance
        )
        let branches: [Double]
        let kind: CurveSurfaceIntersectionKind
        if maximumRadicand <= radicandTolerance {
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
        let firstBase = try configuration.first.surface.point(
            u: angle,
            v: 0.0,
            tolerance: tolerance
        )
        let offset = firstBase - configuration.second.origin
        let secondAxisProjection = configuration.second.axis * offset.dot(
            configuration.second.axis
        )
        let projectedOffset = offset - secondAxisProjection
        let linear = projectedOffset.dot(configuration.projectedAxis)
        let signedDistance = configuration.signedGeneratorDistance(at: angle)
        let rawRadicand = configuration.second.radius * configuration.second.radius
            - signedDistance * signedDistance
        let radicandTolerance = squaredDistanceTolerance(
            radius: configuration.second.radius,
            tolerance: tolerance
        )
        guard rawRadicand >= -radicandTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: sqrt(-rawRadicand),
                tolerance: tolerance,
                message: "Cylinder intersection trace left its analytically classified domain."
            )
        }
        let height = -linear / configuration.projectedAxisSquaredLength
            + branch * sqrt(
                max(0.0, rawRadicand) / configuration.projectedAxisSquaredLength
            )
        return try configuration.first.surface.point(
            u: angle,
            v: height,
            tolerance: tolerance
        )
    }

    private func makeConfiguration(
        first: Cylinder,
        second: Cylinder,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        let axisCross = first.axis.cross(second.axis)
        let normal = try axisCross.normalized(tolerance: tolerance.angle)
        let projectedAxis = first.axis
            - second.axis * first.axis.dot(second.axis)
        let projectedAxisSquaredLength = projectedAxis.dot(projectedAxis)
        guard projectedAxisSquaredLength > tolerance.angle * tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: projectedAxisSquaredLength,
                tolerance: tolerance,
                message: "Cylinder intersection generator solve is singular."
            )
        }
        let centerOffset = first.origin - second.origin
        let harmonicCenter = centerOffset.dot(normal)
        let zeroPoint = try first.surface.point(u: 0.0, v: 0.0, tolerance: tolerance)
        let quarterPoint = try first.surface.point(
            u: Double.pi * 0.5,
            v: 0.0,
            tolerance: tolerance
        )
        return Configuration(
            first: first,
            second: second,
            normal: normal,
            projectedAxis: projectedAxis,
            projectedAxisSquaredLength: projectedAxisSquaredLength,
            harmonicCenter: harmonicCenter,
            harmonicCosine: (zeroPoint - first.origin).dot(normal),
            harmonicSine: (quarterPoint - first.origin).dot(normal)
        )
    }

    private func boundaryAngles(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let amplitude = configuration.harmonicAmplitude
        let numericalThreshold = max(
            Double.ulpOfOne * max(configuration.first.radius, 1.0) * 64.0,
            tolerance.distance * 1.0e-6
        )
        guard amplitude > numericalThreshold else { return [] }
        var values = angles(
            target: configuration.second.radius,
            center: configuration.harmonicCenter,
            cosine: configuration.harmonicCosine,
            sine: configuration.harmonicSine,
            amplitude: amplitude,
            tolerance: tolerance
        )
        values.append(contentsOf: angles(
            target: -configuration.second.radius,
            center: configuration.harmonicCenter,
            cosine: configuration.harmonicCosine,
            sine: configuration.harmonicSine,
            amplitude: amplitude,
            tolerance: tolerance
        ))
        let canonicalValues = values.map { value in
            abs(value - 2.0 * Double.pi) <= tolerance.angle
                ? 0.0
                : value
        }.sorted()
        var result: [Double] = []
        for value in canonicalValues {
            if result.last.map({ abs($0 - value) <= tolerance.angle }) != true {
                result.append(value)
            }
        }
        if result.count > 1,
           let first = result.first,
           let last = result.last,
           first + 2.0 * Double.pi - last <= tolerance.angle {
            result.removeLast()
        }
        return result
    }

    private func angles(
        target: Double,
        center: Double,
        cosine: Double,
        sine: Double,
        amplitude: Double,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let ratio = (target - center) / amplitude
        let ratioTolerance = tolerance.distance / amplitude
        guard ratio >= -1.0 - ratioTolerance,
              ratio <= 1.0 + ratioTolerance else {
            return []
        }
        let clamped = min(max(ratio, -1.0), 1.0)
        let phase = atan2(sine, cosine)
        let offset = acos(clamped)
        return [
            normalizedAngle(phase - offset),
            normalizedAngle(phase + offset),
        ]
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
        abs(configuration.signedGeneratorDistance(at: angle))
            <= configuration.second.radius + tolerance.distance
    }

    private func maximumRadicand(configuration: Configuration) -> Double {
        let lower = configuration.harmonicCenter - configuration.harmonicAmplitude
        let upper = configuration.harmonicCenter + configuration.harmonicAmplitude
        let minimumAbsoluteDistance: Double
        if lower <= 0.0, upper >= 0.0 {
            minimumAbsoluteDistance = 0.0
        } else {
            minimumAbsoluteDistance = min(abs(lower), abs(upper))
        }
        return max(
            0.0,
            configuration.second.radius * configuration.second.radius
                - minimumAbsoluteDistance * minimumAbsoluteDistance
        )
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

    private func precedes(_ lhs: Cylinder, _ rhs: Cylinder) -> Bool {
        let lhsValues = [
            lhs.origin.x, lhs.origin.y, lhs.origin.z,
            lhs.axis.x, lhs.axis.y, lhs.axis.z,
            lhs.radius,
        ]
        let rhsValues = [
            rhs.origin.x, rhs.origin.y, rhs.origin.z,
            rhs.axis.x, rhs.axis.y, rhs.axis.z,
            rhs.radius,
        ]
        for (left, right) in zip(lhsValues, rhsValues) where left != right {
            return left < right
        }
        return false
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

    private func squaredDistanceTolerance(
        radius: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        tolerance.distance * (2.0 * radius + tolerance.distance)
    }
}
