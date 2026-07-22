import Foundation
import CADCore

struct ParallelOffsetTorusCylinderSurfaceIntersector {
    private struct Cylinder {
        let origin: Point3D
        let axis: Vector3D
        let radius: Double

        var surface: Surface3D {
            .analytic(.cylinder(origin: origin, axis: axis, radius: radius))
        }
    }

    private struct Configuration {
        let torus: CanonicalAnalyticSurface.Torus
        let cylinder: Cylinder
        let radialSquaredCenter: Double
        let radialSquaredCosine: Double
        let radialSquaredSine: Double

        var harmonicAmplitude: Double {
            hypot(radialSquaredCosine, radialSquaredSine)
        }

        func radialSquared(at angle: Double) -> Double {
            radialSquaredCenter
                + radialSquaredCosine * cos(angle)
                + radialSquaredSine * sin(angle)
        }

        func radicand(at angle: Double) -> Double {
            let radialDistance = sqrt(max(0.0, radialSquared(at: angle)))
            let tubeRadialDistance = radialDistance - torus.majorRadius
            return torus.minorRadius * torus.minorRadius
                - tubeRadialDistance * tubeRadialDistance
        }
    }

    private struct AngularInterval {
        let lower: Double
        let upper: Double
    }

    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        torus: CanonicalAnalyticSurface.Torus,
        cylinder: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        guard AnalyticAxisRelation.areParallel(torus.axis, cylinder.axis, tolerance: tolerance) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Parallel-offset torus-cylinder intersection requires parallel axes."
            )
        }
        let canonicalCylinder = try canonicalCylinder(
            cylinder,
            torus: torus,
            tolerance: tolerance
        )
        let configuration = try makeConfiguration(
            torus: torus,
            cylinder: canonicalCylinder,
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
        try rejectInternalTangencies(
            roots: roots,
            intervalStates: intervalStates,
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
        let breaks = (0...16).map { Double($0) * Double.pi / 8.0 }
        return try [1.0, -1.0].map { branch in
            try builder.intersection(
                parameterRange: 0.0...(2.0 * Double.pi),
                initialBreaks: breaks,
                kind: .transverse,
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
        let rawRadicand = configuration.radicand(at: angle)
        let radicandTolerance = squaredDistanceTolerance(
            radius: configuration.torus.minorRadius,
            tolerance: tolerance
        )
        guard rawRadicand >= -radicandTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: sqrt(-rawRadicand),
                tolerance: tolerance,
                message: "Torus-cylinder trace left its analytically classified domain."
            )
        }
        let pointOnCylinder = try configuration.cylinder.surface.point(
            u: angle,
            v: 0.0,
            tolerance: tolerance
        )
        return pointOnCylinder
            + configuration.cylinder.axis * (branch * sqrt(max(0.0, rawRadicand)))
    }

    private func makeConfiguration(
        torus: CanonicalAnalyticSurface.Torus,
        cylinder: Cylinder,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        let centerOffset = cylinder.origin - torus.center
        let zeroPoint = try cylinder.surface.point(u: 0.0, v: 0.0, tolerance: tolerance)
        let quarterPoint = try cylinder.surface.point(
            u: Double.pi * 0.5,
            v: 0.0,
            tolerance: tolerance
        )
        let zeroRadial = zeroPoint - cylinder.origin
        let quarterRadial = quarterPoint - cylinder.origin
        return Configuration(
            torus: torus,
            cylinder: cylinder,
            radialSquaredCenter: centerOffset.dot(centerOffset)
                + cylinder.radius * cylinder.radius,
            radialSquaredCosine: 2.0 * centerOffset.dot(zeroRadial),
            radialSquaredSine: 2.0 * centerOffset.dot(quarterRadial)
        )
    }

    private func boundaryAngles(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let lowerRadius = configuration.torus.majorRadius
            - configuration.torus.minorRadius
        let upperRadius = configuration.torus.majorRadius
            + configuration.torus.minorRadius
        let values = [lowerRadius, upperRadius].flatMap { radius in
            boundaryAngles(
                radialDistance: radius,
                configuration: configuration,
                tolerance: tolerance
            )
        }.sorted()
        var result: [Double] = []
        for value in values {
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

    private func boundaryAngles(
        radialDistance: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let amplitude = configuration.harmonicAmplitude
        let numericalThreshold = radialSquaredClassificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        guard amplitude > numericalThreshold else { return [] }
        let ratio = (
            radialDistance * radialDistance
                - configuration.radialSquaredCenter
        ) / amplitude
        let ratioTolerance = numericalThreshold / amplitude
        guard ratio >= -1.0 - ratioTolerance,
              ratio <= 1.0 + ratioTolerance else {
            return []
        }
        let clamped = min(max(ratio, -1.0), 1.0)
        let phase = atan2(
            configuration.radialSquaredSine,
            configuration.radialSquaredCosine
        )
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
        configuration.radicand(at: angle) >= -squaredDistanceTolerance(
            radius: configuration.torus.minorRadius,
            tolerance: tolerance
        ) * 1.0e-6
    }

    private func rejectInternalTangencies(
        roots: [Double],
        intervalStates: [Bool],
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws {
        for index in roots.indices {
            let before = intervalStates[(index + roots.count - 1) % roots.count]
            let after = intervalStates[index]
            if before, after {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: abs(configuration.radicand(at: roots[index])),
                    tolerance: tolerance,
                    message: "Parallel-offset torus-cylinder intersection contains a rank-deficient internal tangency."
                )
            }
        }
    }

    private func canonicalCylinder(
        _ cylinder: CanonicalAnalyticSurface.Cylinder,
        torus: CanonicalAnalyticSurface.Torus,
        tolerance: ModelingTolerance
    ) throws -> Cylinder {
        let torusAxis = try torus.axis.normalized(tolerance: tolerance.distance)
        let cylinderAxis = try cylinder.axis.normalized(tolerance: tolerance.distance)
        let alignedAxis = cylinderAxis.dot(torusAxis) >= 0.0 ? torusAxis : -torusAxis
        let centerOffset = torus.center - cylinder.origin
        let origin = cylinder.origin + alignedAxis * centerOffset.dot(alignedAxis)
        return Cylinder(origin: origin, axis: alignedAxis, radius: cylinder.radius)
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        let period = 2.0 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }

    private func radialSquaredClassificationTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        let outerRadius = configuration.torus.majorRadius
            + configuration.torus.minorRadius
        return max(
            Double.ulpOfOne * max(
                outerRadius * outerRadius,
                configuration.cylinder.radius * configuration.cylinder.radius,
                configuration.radialSquaredCenter,
                1.0
            ) * 128.0,
            squaredDistanceTolerance(radius: outerRadius, tolerance: tolerance) * 1.0e-6
        )
    }

    private func squaredDistanceTolerance(
        radius: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        tolerance.distance * (2.0 * radius + tolerance.distance)
    }
}
