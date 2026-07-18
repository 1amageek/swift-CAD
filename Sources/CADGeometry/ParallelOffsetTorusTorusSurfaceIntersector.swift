import Foundation
import CADCore

struct ParallelOffsetTorusTorusSurfaceIntersector {
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

    private struct Configuration {
        let primary: Torus
        let secondary: Torus
        let radialDirection: Vector3D
        let quarterDirection: Vector3D
        let radialOffset: Double
        let axialOffset: Double
        let characteristicLength: Double

        func point(
            tubeAngle: Double,
            secondaryRadialSign: Double,
            intersectionSign: Double,
            tolerance: ModelingTolerance
        ) throws -> Point3D {
            let cosine = cos(tubeAngle)
            let sine = sin(tubeAngle)
            let primaryRadius = primary.majorRadius + primary.minorRadius * cosine
            let primaryHeight = primary.minorRadius * sine
            let secondaryHeight = axialOffset + primaryHeight
            let secondaryTubeSquared = secondary.minorRadius * secondary.minorRadius
                - secondaryHeight * secondaryHeight
            let algebraicTolerance = tolerance.distance
                * characteristicLength * 8.0
            guard secondaryTubeSquared >= -algebraicTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: -secondaryTubeSquared,
                    tolerance: tolerance,
                    message: "Certified torus-torus trace left the secondary tube-height domain."
                )
            }
            let secondaryTubeRadius = sqrt(max(secondaryTubeSquared, 0.0))
            let secondaryRadius = secondary.majorRadius
                + secondaryRadialSign * secondaryTubeRadius
            let radialCoordinate = (
                primaryRadius * primaryRadius
                    + radialOffset * radialOffset
                    - secondaryRadius * secondaryRadius
            ) / (2.0 * radialOffset)
            let transverseSquared = primaryRadius * primaryRadius
                - radialCoordinate * radialCoordinate
            guard transverseSquared >= -algebraicTolerance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: -transverseSquared,
                    tolerance: tolerance,
                    message: "Certified torus-torus circle branch left its transverse intersection domain."
                )
            }
            return primary.center
                + primary.axis * primaryHeight
                + radialDirection * radialCoordinate
                + quarterDirection * (
                    intersectionSign * sqrt(max(transverseSquared, 0.0))
                )
        }
    }

    private struct Interval {
        let lower: Double
        let upper: Double

        init(_ lower: Double, _ upper: Double) {
            self.lower = min(lower, upper).nextDown
            self.upper = max(lower, upper).nextUp
        }

        static func constant(_ value: Double) -> Interval {
            Interval(value, value)
        }

        var width: Double {
            upper - lower
        }

        var midpoint: Double {
            lower + width * 0.5
        }

        var containsZero: Bool {
            lower <= 0.0 && upper >= 0.0
        }

        func adding(_ other: Interval) -> Interval {
            Interval(lower + other.lower, upper + other.upper)
        }

        func subtracting(_ other: Interval) -> Interval {
            Interval(lower - other.upper, upper - other.lower)
        }

        func multiplied(by other: Interval) -> Interval {
            let values = [
                lower * other.lower,
                lower * other.upper,
                upper * other.lower,
                upper * other.upper,
            ]
            return Interval(values.min() ?? 0.0, values.max() ?? 0.0)
        }

        func divided(by other: Interval) -> Interval? {
            guard other.containsZero == false else { return nil }
            let values = [
                lower / other.lower,
                lower / other.upper,
                upper / other.lower,
                upper / other.upper,
            ]
            return Interval(values.min() ?? 0.0, values.max() ?? 0.0)
        }

        func scaled(by scalar: Double) -> Interval {
            scalar >= 0.0
                ? Interval(lower * scalar, upper * scalar)
                : Interval(upper * scalar, lower * scalar)
        }

        func squared() -> Interval {
            if containsZero {
                return Interval(0.0, max(lower * lower, upper * upper))
            }
            return Interval(
                min(lower * lower, upper * upper),
                max(lower * lower, upper * upper)
            )
        }

        func squareRoot() -> Interval? {
            guard lower >= 0.0 else { return nil }
            return Interval(sqrt(lower), sqrt(upper))
        }
    }

    func intersections(
        first: CanonicalAnalyticSurface.Torus,
        second: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let firstTorus = try canonicalTorus(first, tolerance: tolerance)
        let secondTorus = try canonicalTorus(second, tolerance: tolerance)
        guard AnalyticAxisRelation.areParallel(
            firstTorus.axis,
            secondTorus.axis,
            tolerance: tolerance
        ) else {
            throw unsupported(
                residual: firstTorus.axis.cross(secondTorus.axis).length,
                tolerance: tolerance,
                message: "Offset torus-torus intersection requires parallel axes."
            )
        }
        if boundingSpheresAreSeparated(
            first: firstTorus,
            second: secondTorus,
            tolerance: tolerance
        ) {
            return []
        }

        let ordered = stableOrder(firstTorus, secondTorus)
        let configuration = try makeConfiguration(
            primary: ordered.primary,
            secondary: ordered.secondary,
            tolerance: tolerance
        )
        try certifyFullDomainBranches(
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
        let segmentCount = min(16, max(1, options.maximumSeedCount))
        let breaks = (0...segmentCount).map {
            Double($0) * 2.0 * Double.pi / Double(segmentCount)
        }
        var result: [SurfaceSurfaceIntersection] = []
        for secondaryRadialSign in [-1.0, 1.0] {
            for intersectionSign in [-1.0, 1.0] {
                result.append(try builder.intersection(
                    parameterRange: 0.0...(2.0 * Double.pi),
                    initialBreaks: breaks,
                    kind: .transverse,
                    pointAt: { tubeAngle in
                        try configuration.point(
                            tubeAngle: tubeAngle,
                            secondaryRadialSign: secondaryRadialSign,
                            intersectionSign: intersectionSign,
                            tolerance: tolerance
                        )
                    }
                ))
            }
        }
        return result
    }

    private func makeConfiguration(
        primary: Torus,
        secondary: Torus,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        let centerOffset = secondary.center - primary.center
        let axialCenterOffset = centerOffset.dot(primary.axis)
        let radialCenterOffset = centerOffset - primary.axis * axialCenterOffset
        let radialOffset = radialCenterOffset.length
        guard radialOffset > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: radialOffset,
                tolerance: tolerance,
                message: "Offset torus-torus intersection requires distinct parallel axes."
            )
        }
        let radialDirection = try radialCenterOffset.normalized(
            tolerance: tolerance.distance
        )
        let quarterDirection = try primary.axis.cross(radialDirection).normalized(
            tolerance: tolerance.distance
        )
        return Configuration(
            primary: primary,
            secondary: secondary,
            radialDirection: radialDirection,
            quarterDirection: quarterDirection,
            radialOffset: radialOffset,
            axialOffset: -axialCenterOffset,
            characteristicLength: max(
                primary.majorRadius + primary.minorRadius,
                secondary.majorRadius + secondary.minorRadius,
                centerOffset.length,
                1.0
            )
        )
    }

    private func certifyFullDomainBranches(
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws {
        let maximumDepth = min(options.maximumSubdivisionDepth + 12, 24)
        var processedCellCount = 0
        for secondaryRadialSign in [-1.0, 1.0] {
            try certify(
                angle: Interval(0.0, 2.0 * Double.pi),
                secondaryRadialSign: secondaryRadialSign,
                depth: 0,
                maximumDepth: maximumDepth,
                maximumCellCount: min(
                    max(options.maximumSeedCount * 16, 4_096),
                    65_536
                ),
                processedCellCount: &processedCellCount,
                configuration: configuration,
                tolerance: tolerance
            )
        }
    }

    private func certify(
        angle: Interval,
        secondaryRadialSign: Double,
        depth: Int,
        maximumDepth: Int,
        maximumCellCount: Int,
        processedCellCount: inout Int,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws {
        processedCellCount += 1
        guard processedCellCount <= maximumCellCount else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: Double(processedCellCount),
                tolerance: tolerance,
                message: "Offset torus-torus branch certification exceeded its cell limit."
            )
        }
        if branchIsCertified(
            angle: angle,
            secondaryRadialSign: secondaryRadialSign,
            configuration: configuration,
            tolerance: tolerance
        ) {
            return
        }
        guard depth < maximumDepth else {
            throw unsupported(
                residual: angle.width,
                tolerance: tolerance,
                message: "Offset torus-torus intersection could not certify four full-domain simple transverse branches."
            )
        }
        let middle = angle.midpoint
        try certify(
            angle: Interval(angle.lower, middle),
            secondaryRadialSign: secondaryRadialSign,
            depth: depth + 1,
            maximumDepth: maximumDepth,
            maximumCellCount: maximumCellCount,
            processedCellCount: &processedCellCount,
            configuration: configuration,
            tolerance: tolerance
        )
        try certify(
            angle: Interval(middle, angle.upper),
            secondaryRadialSign: secondaryRadialSign,
            depth: depth + 1,
            maximumDepth: maximumDepth,
            maximumCellCount: maximumCellCount,
            processedCellCount: &processedCellCount,
            configuration: configuration,
            tolerance: tolerance
        )
    }

    private func branchIsCertified(
        angle: Interval,
        secondaryRadialSign: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) -> Bool {
        let cosine = cosineInterval(angle)
        let sine = sineInterval(angle)
        let primaryRadius = Interval.constant(configuration.primary.majorRadius)
            .adding(cosine.scaled(by: configuration.primary.minorRadius))
        guard primaryRadius.lower > tolerance.distance else { return false }
        let secondaryHeight = Interval.constant(configuration.axialOffset)
            .adding(sine.scaled(by: configuration.primary.minorRadius))
        let secondaryTubeSquared = Interval.constant(
            configuration.secondary.minorRadius
                * configuration.secondary.minorRadius
        ).subtracting(secondaryHeight.squared())
        guard let secondaryTubeRadius = secondaryTubeSquared.squareRoot() else {
            return false
        }
        let secondaryRadius = Interval.constant(configuration.secondary.majorRadius)
            .adding(secondaryTubeRadius.scaled(by: secondaryRadialSign))
        guard secondaryRadius.lower > tolerance.distance else { return false }

        let radialNumerator = primaryRadius.squared()
            .adding(.constant(
                configuration.radialOffset * configuration.radialOffset
            ))
            .subtracting(secondaryRadius.squared())
        let radialDenominator = primaryRadius.scaled(
            by: 2.0 * configuration.radialOffset
        )
        guard let circleCosine = radialNumerator.divided(by: radialDenominator) else {
            return false
        }
        let circleMargin = max(
            tolerance.distance / configuration.characteristicLength * 8.0,
            Double.ulpOfOne * 1_024.0
        )
        guard circleCosine.lower > -1.0 + circleMargin,
              circleCosine.upper < 1.0 - circleMargin else {
            return false
        }

        let radialDotNumerator = primaryRadius.squared()
            .adding(secondaryRadius.squared())
            .subtracting(.constant(
                configuration.radialOffset * configuration.radialOffset
            ))
        let radialDotDenominator = primaryRadius.multiplied(by: secondaryRadius)
            .scaled(by: 2.0)
        guard let radialDot = radialDotNumerator.divided(by: radialDotDenominator) else {
            return false
        }
        let secondaryCosine = secondaryTubeRadius.scaled(
            by: secondaryRadialSign / configuration.secondary.minorRadius
        )
        let secondarySine = secondaryHeight.scaled(
            by: 1.0 / configuration.secondary.minorRadius
        )
        let normalDot = cosine.multiplied(by: secondaryCosine)
            .multiplied(by: radialDot)
            .adding(sine.multiplied(by: secondarySine))
        let normalMargin = max(
            tolerance.angle * 8.0,
            Double.ulpOfOne * 1_024.0
        )
        return normalDot.lower > -1.0 + normalMargin
            && normalDot.upper < 1.0 - normalMargin
    }

    private func boundingSpheresAreSeparated(
        first: Torus,
        second: Torus,
        tolerance: ModelingTolerance
    ) -> Bool {
        let firstRadius = first.majorRadius + first.minorRadius
        let secondRadius = second.majorRadius + second.minorRadius
        return (first.center - second.center).length
            > firstRadius + secondRadius + tolerance.distance
    }

    private func stableOrder(
        _ first: Torus,
        _ second: Torus
    ) -> (primary: Torus, secondary: Torus) {
        if torusKey(first).lexicographicallyPrecedes(torusKey(second)) {
            return (first, second)
        }
        return (second, first)
    }

    private func torusKey(_ torus: Torus) -> [Double] {
        [
            torus.minorRadius,
            torus.majorRadius,
            torus.center.x,
            torus.center.y,
            torus.center.z,
            torus.axis.x,
            torus.axis.y,
            torus.axis.z,
        ]
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

    private func cosineInterval(_ angle: Interval) -> Interval {
        trigonometricInterval(angle, phase: 0.0)
    }

    private func sineInterval(_ angle: Interval) -> Interval {
        trigonometricInterval(angle, phase: Double.pi * 0.5)
    }

    private func trigonometricInterval(
        _ angle: Interval,
        phase: Double
    ) -> Interval {
        guard angle.width < 2.0 * Double.pi else {
            return Interval(-1.0, 1.0)
        }
        let first = cos(angle.lower - phase)
        let second = cos(angle.upper - phase)
        var lower = min(first, second)
        var upper = max(first, second)
        if containsPeriodicValue(
            angle,
            value: phase,
            period: 2.0 * Double.pi
        ) {
            upper = 1.0
        }
        if containsPeriodicValue(
            angle,
            value: phase + Double.pi,
            period: 2.0 * Double.pi
        ) {
            lower = -1.0
        }
        return Interval(lower, upper)
    }

    private func containsPeriodicValue(
        _ interval: Interval,
        value: Double,
        period: Double
    ) -> Bool {
        let firstIndex = ceil((interval.lower - value) / period)
        return value + firstIndex * period <= interval.upper
    }

    private func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }

    private func unsupported(
        residual: Double,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .unsupportedCapability,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
