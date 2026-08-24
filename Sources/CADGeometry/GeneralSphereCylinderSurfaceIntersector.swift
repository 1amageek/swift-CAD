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
        let sphereSurface: Surface3D
        let cylinderSurface: Surface3D
        if case .sphere = CanonicalAnalyticSurface(firstSurface) {
            sphereSurface = firstSurface
            cylinderSurface = secondSurface
        } else {
            sphereSurface = secondSurface
            cylinderSurface = firstSurface
        }
        let canonicalCylinder = try canonicalCylinder(cylinder, tolerance: tolerance)
        let poleSplitNodes = try CertifiedSphereCylinderIntersectionCurve
            .poleSplitNodes(
                sphereSurface: sphereSurface,
                cylinderSurface: cylinderSurface,
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
            if poleSplitNodes.isEmpty == false {
                return try fullDomainPoleSplitIntersections(
                    nodes: poleSplitNodes,
                    builder: builder,
                    sphereSurface: sphereSurface,
                    cylinderSurface: cylinderSurface,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    tolerance: tolerance
                )
            }
            return try fullDomainIntersections(
                builder: builder,
                sphereSurface: sphereSurface,
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
            let intervalNodes = poleSplitNodes.filter {
                adjustedAngle($0.angle, inside: interval) >= lower - tolerance.angle
                    && adjustedAngle($0.angle, inside: interval) <= upper + tolerance.angle
            }
            if intervalNodes.isEmpty {
                results.append(try intervalIntersection(
                    interval: interval,
                    builder: builder,
                    sphereSurface: sphereSurface,
                    cylinderSurface: cylinderSurface,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    tolerance: tolerance
                ))
            } else {
                results.append(contentsOf: try poleSplitIntersections(
                    interval: interval,
                    nodes: intervalNodes,
                    kind: .mixed,
                    builder: builder,
                    sphereSurface: sphereSurface,
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

    private func fullDomainPoleSplitIntersections(
        nodes: [(angle: Double, branch: Double)],
        builder: SurfaceIntersectionSplineBuilder,
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        var results: [SurfaceSurfaceIntersection] = []
        for branch in [-1.0, 1.0] {
            let branchAngles = nodes
                .filter { $0.branch == branch }
                .map(\.angle)
                .sorted()
            guard let first = branchAngles.first else {
                let componentKind: CertifiedSphereCylinderIntersectionCurve.ComponentKind
                    = branch < 0.0 ? .negativeFullBranch : .positiveFullBranch
                results.append(try fullDomainIntersection(
                    componentKind: componentKind,
                    builder: builder,
                    sphereSurface: sphereSurface,
                    cylinderSurface: cylinderSurface,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    tolerance: tolerance
                ))
                continue
            }
            let boundaries = branchAngles + [first + 2.0 * Double.pi]
            for index in branchAngles.indices {
                results.append(try poleSplitIntersection(
                    lowerAngle: boundaries[index],
                    upperAngle: boundaries[index + 1],
                    branch: branch,
                    kind: .transverse,
                    builder: builder,
                    sphereSurface: sphereSurface,
                    cylinderSurface: cylinderSurface,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    tolerance: tolerance
                ))
            }
        }
        return results
    }

    private func poleSplitIntersections(
        interval: AngularInterval,
        nodes: [(angle: Double, branch: Double)],
        kind: CurveSurfaceIntersectionKind,
        builder: SurfaceIntersectionSplineBuilder,
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        var results: [SurfaceSurfaceIntersection] = []
        for branch in [-1.0, 1.0] {
            let interior = nodes
                .filter { $0.branch == branch }
                .map { adjustedAngle($0.angle, inside: interval) }
                .sorted()
            var boundaries = [interval.lower]
            boundaries.append(contentsOf: interior)
            boundaries.append(interval.upper)
            for index in 0..<(boundaries.count - 1) where
                boundaries[index + 1] - boundaries[index] > tolerance.angle {
                results.append(try poleSplitIntersection(
                    lowerAngle: boundaries[index],
                    upperAngle: boundaries[index + 1],
                    branch: branch,
                    kind: kind,
                    builder: builder,
                    sphereSurface: sphereSurface,
                    cylinderSurface: cylinderSurface,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    tolerance: tolerance
                ))
            }
        }
        return results
    }

    private func poleSplitIntersection(
        lowerAngle: Double,
        upperAngle: Double,
        branch: Double,
        kind: CurveSurfaceIntersectionKind,
        builder: SurfaceIntersectionSplineBuilder,
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let componentKind: CertifiedSphereCylinderIntersectionCurve.ComponentKind
            = branch < 0.0
                ? .negativeOpenAngularInterval
                : .positiveOpenAngularInterval
        let proceduralCurve = try CertifiedSphereCylinderIntersectionCurve(
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
            componentKind: componentKind,
            lowerAngle: lowerAngle,
            upperAngle: upperAngle,
            tolerance: tolerance
        )
        return try splineIntersection(
            proceduralCurve: proceduralCurve,
            builder: builder,
            initialBreaks: (0...8).map { Double($0) / 8.0 },
            kind: kind,
            isClosed: false,
            providesRegularParameterDifferentials: false,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
    }

    private func fullDomainIntersections(
        builder: SurfaceIntersectionSplineBuilder,
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        try [
            CertifiedSphereCylinderIntersectionCurve.ComponentKind
                .positiveFullBranch,
            .negativeFullBranch,
        ].map { componentKind in
            try fullDomainIntersection(
                componentKind: componentKind,
                builder: builder,
                sphereSurface: sphereSurface,
                cylinderSurface: cylinderSurface,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }
    }

    private func fullDomainIntersection(
        componentKind: CertifiedSphereCylinderIntersectionCurve.ComponentKind,
        builder: SurfaceIntersectionSplineBuilder,
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let proceduralCurve = try CertifiedSphereCylinderIntersectionCurve(
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
            componentKind: componentKind,
            lowerAngle: 0.0,
            upperAngle: 2.0 * Double.pi,
            tolerance: tolerance
        )
        return try splineIntersection(
            proceduralCurve: proceduralCurve,
            builder: builder,
            initialBreaks: (0...16).map { Double($0) / 16.0 },
            kind: .transverse,
            isClosed: true,
            providesRegularParameterDifferentials: true,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
    }

    private func intervalIntersection(
        interval: AngularInterval,
        builder: SurfaceIntersectionSplineBuilder,
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let proceduralCurve = try CertifiedSphereCylinderIntersectionCurve(
            sphereSurface: sphereSurface,
            cylinderSurface: cylinderSurface,
            componentKind: .boundedAngularInterval,
            lowerAngle: interval.lower,
            upperAngle: interval.upper,
            tolerance: tolerance
        )
        return try splineIntersection(
            proceduralCurve: proceduralCurve,
            builder: builder,
            initialBreaks: (0...8).map { Double($0) / 8.0 },
            kind: .mixed,
            isClosed: true,
            providesRegularParameterDifferentials: true,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
    }

    private func splineIntersection(
        proceduralCurve: CertifiedSphereCylinderIntersectionCurve,
        builder: SurfaceIntersectionSplineBuilder,
        initialBreaks: [Double],
        kind: CurveSurfaceIntersectionKind,
        isClosed: Bool,
        providesRegularParameterDifferentials: Bool,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            sphereCylinderCurve: proceduralCurve,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        let firstParameterCurve = truth.firstSurfaceParameterCurve
        let secondParameterCurve = truth.secondSurfaceParameterCurve
        let firstParameterAt: (Double) throws -> SurfaceParameter = { fraction in
            try firstParameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        }
        let secondParameterAt: (Double) throws -> SurfaceParameter = { fraction in
            try secondParameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        }
        let pointFirstDerivativeAt: (Double) throws -> Vector3D = { fraction in
            try truth.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            ).firstDerivative
        }
        let pointAt: (Double) throws -> Point3D = { fraction in
            try truth.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        }
        let derived: SurfaceSurfaceIntersection
        if providesRegularParameterDifferentials {
            derived = try builder.intersection(
                parameterRange: 0.0...1.0,
                initialBreaks: initialBreaks,
                kind: kind,
                isClosed: isClosed,
                firstParameterAt: firstParameterAt,
                secondParameterAt: secondParameterAt,
                firstParameterDifferentialAt: { fraction in
                    try firstParameterCurve.differentialGeometry(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                },
                secondParameterDifferentialAt: { fraction in
                    try secondParameterCurve.differentialGeometry(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                },
                pointFirstDerivativeAt: pointFirstDerivativeAt,
                pointAt: pointAt
            )
        } else {
            derived = try builder.intersection(
                parameterRange: 0.0...1.0,
                initialBreaks: initialBreaks,
                kind: kind,
                isClosed: isClosed,
                firstParameterAt: firstParameterAt,
                secondParameterAt: secondParameterAt,
                pointFirstDerivativeAt: pointFirstDerivativeAt,
                pointAt: pointAt
            )
        }
        return try certifiedIntersection(derived, truth: truth, tolerance: tolerance)
    }

    private func certifiedIntersection(
        _ derived: SurfaceSurfaceIntersection,
        truth: CertifiedAnalyticAnalyticIntersectionCurve,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        guard case let .curve(derivedCurve) = derived else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A regular sphere-cylinder component did not produce a derived curve cache."
            )
        }
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

    private func adjustedAngle(
        _ angle: Double,
        inside interval: AngularInterval
    ) -> Double {
        let period = 2.0 * Double.pi
        var adjusted = normalizedAngle(angle)
        while adjusted < interval.lower {
            adjusted += period
        }
        while adjusted > interval.upper, adjusted - period >= interval.lower {
            adjusted -= period
        }
        return adjusted
    }

    private func squaredDistanceTolerance(
        radius: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        tolerance.distance * (2.0 * radius + tolerance.distance)
    }
}
