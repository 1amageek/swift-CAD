import Foundation
import CADCore

struct GeneralSphereCylinderSurfaceIntersector {
    private struct Cylinder {
        let origin: Point3D
        let axis: Vector3D
        let radius: Double

        var surface: Surface3D {
            .analytic(.cylinder(origin: origin, axis: axis, radius: radius))
        }
    }

    private struct Configuration {
        let sphere: CanonicalAnalyticSurface.Sphere
        let cylinder: Cylinder
        let axialCenter: Double
        let harmonicCenter: Double
        let harmonicCosine: Double
        let harmonicSine: Double

        var harmonicAmplitude: Double {
            hypot(harmonicCosine, harmonicSine)
        }

        func radicand(at angle: Double) -> Double {
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
        sphere: CanonicalAnalyticSurface.Sphere,
        cylinder: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let canonicalCylinder = try canonicalCylinder(cylinder, tolerance: tolerance)
        try rejectSphereParameterPoleContacts(
            sphere: sphere,
            cylinder: canonicalCylinder,
            tolerance: tolerance
        )
        let configuration = try makeConfiguration(
            sphere: sphere,
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
            radius: configuration.sphere.radius,
            tolerance: tolerance
        )
        guard rawRadicand >= -radicandTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: sqrt(-rawRadicand),
                tolerance: tolerance,
                message: "Sphere-cylinder trace left its analytically classified domain."
            )
        }
        let height = -configuration.axialCenter
            + branch * sqrt(max(0.0, rawRadicand))
        return try configuration.cylinder.surface.point(
            u: angle,
            v: height,
            tolerance: tolerance
        )
    }

    private func makeConfiguration(
        sphere: CanonicalAnalyticSurface.Sphere,
        cylinder: Cylinder,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        let centerOffset = cylinder.origin - sphere.center
        let axialCenter = centerOffset.dot(cylinder.axis)
        let radialCenterOffset = centerOffset - cylinder.axis * axialCenter
        let zeroPoint = try cylinder.surface.point(u: 0.0, v: 0.0, tolerance: tolerance)
        let quarterPoint = try cylinder.surface.point(
            u: Double.pi * 0.5,
            v: 0.0,
            tolerance: tolerance
        )
        let zeroRadial = zeroPoint - cylinder.origin
        let quarterRadial = quarterPoint - cylinder.origin
        return Configuration(
            sphere: sphere,
            cylinder: cylinder,
            axialCenter: axialCenter,
            harmonicCenter: sphere.radius * sphere.radius
                - radialCenterOffset.dot(radialCenterOffset)
                - cylinder.radius * cylinder.radius,
            harmonicCosine: -2.0 * radialCenterOffset.dot(zeroRadial),
            harmonicSine: -2.0 * radialCenterOffset.dot(quarterRadial)
        )
    }

    private func boundaryAngles(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let amplitude = configuration.harmonicAmplitude
        let numericalThreshold = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        guard amplitude > numericalThreshold else { return [] }
        let ratio = -configuration.harmonicCenter / amplitude
        let ratioTolerance = numericalThreshold / amplitude
        guard ratio >= -1.0 - ratioTolerance,
              ratio <= 1.0 + ratioTolerance else {
            return []
        }
        let clamped = min(max(ratio, -1.0), 1.0)
        let phase = atan2(
            configuration.harmonicSine,
            configuration.harmonicCosine
        )
        let offset = acos(clamped)
        let values = [
            normalizedAngle(phase - offset),
            normalizedAngle(phase + offset),
        ].sorted()
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
        configuration.radicand(at: angle) >= -classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
    }

    private func classificationTolerance(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Double {
        max(
            Double.ulpOfOne * max(
                configuration.sphere.radius * configuration.sphere.radius,
                configuration.cylinder.radius * configuration.cylinder.radius,
                1.0
            ) * 128.0,
            squaredDistanceTolerance(
                radius: configuration.sphere.radius,
                tolerance: tolerance
            ) * 1.0e-6
        )
    }

    private func rejectSphereParameterPoleContacts(
        sphere: CanonicalAnalyticSurface.Sphere,
        cylinder: Cylinder,
        tolerance: ModelingTolerance
    ) throws {
        for sign in [-1.0, 1.0] {
            let pole = sphere.center + Vector3D.unitZ * (sign * sphere.radius)
            let offset = pole - cylinder.origin
            let axialDistance = offset.dot(cylinder.axis)
            let radialDistance = (offset - cylinder.axis * axialDistance).length
            if abs(radialDistance - cylinder.radius) <= tolerance.distance {
                throw KernelError(
                    phase: .geometry,
                    code: .unsupportedCapability,
                    residual: abs(radialDistance - cylinder.radius),
                    tolerance: tolerance,
                    message: "Sphere-cylinder intersections through a spherical parameter pole are outside the current exact pcurve envelope."
                )
            }
        }
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
