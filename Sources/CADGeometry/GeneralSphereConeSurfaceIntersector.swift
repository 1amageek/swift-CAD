import Foundation
import CADCore

struct GeneralSphereConeSurfaceIntersector {
    private struct Cone {
        let apex: Point3D
        let axis: Vector3D
        let halfAngle: Double

        var surface: Surface3D {
            .analytic(.cone(apex: apex, axis: axis, halfAngle: halfAngle))
        }
    }

    private struct Configuration {
        let sphere: CanonicalAnalyticSurface.Sphere
        let cone: Cone
        let axialCenter: Double
        let radialCosine: Double
        let radialSine: Double
        let quadraticA: Double
        let quadraticC: Double

        var radialAmplitude: Double {
            hypot(radialCosine, radialSine)
        }

        var slope: Double {
            tan(cone.halfAngle)
        }

        func halfLinear(at angle: Double) -> Double {
            axialCenter + slope * (
                radialCosine * cos(angle) + radialSine * sin(angle)
            )
        }

        func radicand(at angle: Double) -> Double {
            let halfLinear = halfLinear(at: angle)
            return halfLinear * halfLinear - quadraticA * quadraticC
        }
    }

    private struct AngularInterval {
        let lower: Double
        let upper: Double
    }

    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersections(
        sphere: CanonicalAnalyticSurface.Sphere,
        cone: CanonicalAnalyticSurface.Cone,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let sphereSurface: Surface3D
        let coneSurface: Surface3D
        if case .sphere = CanonicalAnalyticSurface(firstSurface) {
            sphereSurface = firstSurface
            coneSurface = secondSurface
        } else {
            sphereSurface = secondSurface
            coneSurface = firstSurface
        }
        let canonicalCone = try canonicalCone(cone, tolerance: tolerance)
        try rejectSingularContacts(
            sphere: sphere,
            cone: canonicalCone,
            tolerance: tolerance
        )
        let configuration = try makeConfiguration(
            sphere: sphere,
            cone: canonicalCone,
            tolerance: tolerance
        )
        let roots = boundaryAngles(
            configuration: configuration,
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
            return try fullDomainIntersections(
                configuration: configuration,
                builder: builder,
                sphereSurface: sphereSurface,
                coneSurface: coneSurface,
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
                sphereSurface: sphereSurface,
                coneSurface: coneSurface,
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
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let breaks = (0...16).map { Double($0) / 16.0 }
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
                coneSurface: coneSurface,
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
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
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
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
    }

    private func certifiedIntersection(
        _ derived: SurfaceSurfaceIntersection,
        componentKind: CertifiedSphereConeIntersectionCurve.ComponentKind,
        lowerAngle: Double,
        upperAngle: Double,
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        guard case let .curve(derivedCurve) = derived else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A regular sphere-cone component did not produce a derived curve cache."
            )
        }
        let proceduralCurve = try CertifiedSphereConeIntersectionCurve(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            componentKind: componentKind,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            tolerance: tolerance
        )
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            sphereConeCurve: proceduralCurve,
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
        let rawRadicand = configuration.radicand(at: angle)
        let radicandTolerance = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        guard rawRadicand >= -radicandTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: sqrt(-rawRadicand),
                tolerance: tolerance,
                message: "Sphere-cone trace left its analytically classified domain."
            )
        }
        let axialParameter = (
            configuration.halfLinear(at: angle)
                + branch * sqrt(max(0.0, rawRadicand))
        ) / configuration.quadraticA
        let slantParameter = axialParameter / cos(configuration.cone.halfAngle)
        return try configuration.cone.surface.point(
            u: angle,
            v: slantParameter,
            tolerance: tolerance
        )
    }

    private func makeConfiguration(
        sphere: CanonicalAnalyticSurface.Sphere,
        cone: Cone,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        let centerOffset = sphere.center - cone.apex
        let axialCenter = centerOffset.dot(cone.axis)
        let radialCenter = centerOffset - cone.axis * axialCenter
        let zeroPoint = try cone.surface.point(u: 0.0, v: 1.0, tolerance: tolerance)
        let quarterPoint = try cone.surface.point(
            u: Double.pi * 0.5,
            v: 1.0,
            tolerance: tolerance
        )
        let axialStep = cone.axis * cos(cone.halfAngle)
        let sine = sin(cone.halfAngle)
        let zeroRadial = (zeroPoint - cone.apex - axialStep) / sine
        let quarterRadial = (quarterPoint - cone.apex - axialStep) / sine
        let slope = tan(cone.halfAngle)
        return Configuration(
            sphere: sphere,
            cone: cone,
            axialCenter: axialCenter,
            radialCosine: radialCenter.dot(zeroRadial),
            radialSine: radialCenter.dot(quarterRadial),
            quadraticA: 1.0 + slope * slope,
            quadraticC: centerOffset.dot(centerOffset)
                - sphere.radius * sphere.radius
        )
    }

    private func boundaryAngles(
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> [Double] {
        let product = configuration.quadraticA * configuration.quadraticC
        let numericalThreshold = classificationTolerance(
            configuration: configuration,
            tolerance: tolerance
        )
        guard product >= -numericalThreshold else { return [] }
        let root = sqrt(max(0.0, product))
        let linearThreshold = sqrt(numericalThreshold)
        let targets = root <= linearThreshold
            ? [-configuration.axialCenter / configuration.slope]
            : [
                (root - configuration.axialCenter) / configuration.slope,
                (-root - configuration.axialCenter) / configuration.slope,
            ]
        let amplitude = configuration.radialAmplitude
        guard amplitude > tolerance.distance else { return [] }
        let phase = atan2(configuration.radialSine, configuration.radialCosine)
        var values: [Double] = []
        for target in targets {
            let ratio = target / amplitude
            let ratioTolerance = linearThreshold / amplitude
            guard ratio >= -1.0 - ratioTolerance,
                  ratio <= 1.0 + ratioTolerance else {
                continue
            }
            let offset = acos(min(max(ratio, -1.0), 1.0))
            values.append(normalizedAngle(phase - offset))
            values.append(normalizedAngle(phase + offset))
        }
        values.sort()
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
        let scale = max(
            configuration.sphere.radius,
            abs(configuration.axialCenter),
            configuration.radialAmplitude,
            1.0
        )
        return max(
            Double.ulpOfOne * scale * scale * 256.0,
            tolerance.distance * (2.0 * scale + tolerance.distance) * 1.0e-6
        )
    }

    private func rejectSingularContacts(
        sphere: CanonicalAnalyticSurface.Sphere,
        cone: Cone,
        tolerance: ModelingTolerance
    ) throws {
        let apexResidual = abs((sphere.center - cone.apex).length - sphere.radius)
        if apexResidual <= tolerance.distance {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: apexResidual,
                tolerance: tolerance,
                message: "Sphere-cone intersection passes through the cone's singular apex parameter."
            )
        }
        let slope = tan(cone.halfAngle)
        for sign in [-1.0, 1.0] {
            let pole = sphere.center + Vector3D.unitZ * (sign * sphere.radius)
            let offset = pole - cone.apex
            let axialDistance = offset.dot(cone.axis)
            let radialDistance = (offset - cone.axis * axialDistance).length
            let residual = abs(radialDistance - abs(axialDistance) * slope)
            if residual <= tolerance.distance {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Sphere-cone intersection passes through a singular spherical parameter pole."
                )
            }
        }
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
