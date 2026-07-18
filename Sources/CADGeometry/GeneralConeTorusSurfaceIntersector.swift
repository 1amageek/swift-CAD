import Foundation
import CADCore

struct GeneralConeTorusSurfaceIntersector {
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
        let cone: Cone
        let torus: Torus
        let centerDirection: Vector3D
        let zeroRadial: Vector3D
        let quarterRadial: Vector3D
        let lowerSlant: Double
        let upperSlant: Double
        let characteristicLength: Double

        func direction(at angle: Double) -> Vector3D {
            centerDirection
                + zeroRadial * cos(angle)
                + quarterRadial * sin(angle)
        }

        func generatorPoint(angle: Double, slant: Double) -> Point3D {
            cone.apex + direction(at: angle) * slant
        }

        func coefficients(at angle: Double) -> [Double] {
            let offset = cone.apex - torus.center
            let direction = direction(at: angle)
            let pointSquared = offset.dot(offset)
            let pointDirection = offset.dot(direction)
            let axialPoint = offset.dot(torus.axis)
            let axialDirection = direction.dot(torus.axis)
            let q0 = pointSquared
                + torus.majorRadius * torus.majorRadius
                - torus.minorRadius * torus.minorRadius
            let q1 = 2.0 * pointDirection
            let radial0 = pointSquared - axialPoint * axialPoint
            let radial1 = 2.0 * (
                pointDirection - axialPoint * axialDirection
            )
            let radial2 = 1.0 - axialDirection * axialDirection
            let majorFactor = 4.0 * torus.majorRadius * torus.majorRadius
            return [
                q0 * q0 - majorFactor * radial0,
                2.0 * q0 * q1 - majorFactor * radial1,
                q1 * q1 + 2.0 * q0 - majorFactor * radial2,
                2.0 * q1,
                1.0,
            ]
        }
    }

    private struct Cell {
        let angle: Interval
        let slant: Interval
        let depth: Int
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
            let products = [
                lower * other.lower,
                lower * other.upper,
                upper * other.lower,
                upper * other.upper,
            ]
            return Interval(products.min() ?? 0.0, products.max() ?? 0.0)
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
    }

    func intersections(
        cone: CanonicalAnalyticSurface.Cone,
        torus: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let canonicalCone = try canonicalCone(cone, tolerance: tolerance)
        let canonicalTorus = try canonicalTorus(torus, tolerance: tolerance)
        let axesAreParallel = AnalyticAxisRelation.areParallel(
            canonicalCone.axis,
            canonicalTorus.axis,
            tolerance: tolerance
        )
        let radialOffset = AnalyticAxisRelation.radialOffset(
            from: canonicalTorus.center,
            axis: canonicalTorus.axis,
            to: canonicalCone.apex
        )
        guard axesAreParallel == false || radialOffset.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "General cone-torus intersection requires non-coaxial surfaces."
            )
        }
        try rejectApexContact(
            cone: canonicalCone,
            torus: canonicalTorus,
            tolerance: tolerance
        )
        let configuration = try makeConfiguration(
            cone: canonicalCone,
            torus: canonicalTorus,
            tolerance: tolerance
        )
        try certifyConstantSimpleGeneratorRoots(
            configuration: configuration,
            options: options,
            tolerance: tolerance
        )
        let initialRoots = try verifiedRoots(
            angle: 0.0,
            configuration: configuration,
            tolerance: tolerance
        )
        guard initialRoots.isEmpty == false else {
            return []
        }
        let builder = SurfaceIntersectionSplineBuilder(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )
        let breaks = (0...32).map { Double($0) * Double.pi / 16.0 }
        return try initialRoots.indices.map { branchIndex in
            try builder.intersection(
                parameterRange: 0.0...(2.0 * Double.pi),
                initialBreaks: breaks,
                kind: .transverse,
                pointAt: { angle in
                    let roots = try verifiedRoots(
                        angle: angle,
                        configuration: configuration,
                        tolerance: tolerance
                    )
                    guard roots.count == initialRoots.count else {
                        throw KernelError(
                            phase: .geometry,
                            code: .intersectionFailure,
                            residual: Double(abs(roots.count - initialRoots.count)),
                            tolerance: tolerance,
                            message: "Certified cone-torus generator root count changed during tracing."
                        )
                    }
                    return configuration.generatorPoint(
                        angle: angle,
                        slant: roots[branchIndex]
                    )
                }
            )
        }
    }

    private func makeConfiguration(
        cone: Cone,
        torus: Torus,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        let surface = cone.surface
        let centerDirection = cone.axis * cos(cone.halfAngle)
        let zeroPoint = try surface.point(u: 0.0, v: 1.0, tolerance: tolerance)
        let quarterPoint = try surface.point(
            u: Double.pi * 0.5,
            v: 1.0,
            tolerance: tolerance
        )
        let outerRadius = torus.majorRadius + torus.minorRadius
        let slantBound = (torus.center - cone.apex).length
            + outerRadius
            + tolerance.distance * 16.0
        return Configuration(
            cone: cone,
            torus: torus,
            centerDirection: centerDirection,
            zeroRadial: zeroPoint - cone.apex - centerDirection,
            quarterRadial: quarterPoint - cone.apex - centerDirection,
            lowerSlant: -slantBound,
            upperSlant: slantBound,
            characteristicLength: max(
                outerRadius,
                (torus.center - cone.apex).length,
                1.0
            )
        )
    }

    private func certifyConstantSimpleGeneratorRoots(
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws {
        let maximumDepth = min(options.maximumSubdivisionDepth + 12, 24)
        let maximumCellCount = min(
            max(options.maximumSeedCount * 64, 16_384),
            65_536
        )
        var cells = [Cell(
            angle: Interval(0.0, 2.0 * Double.pi),
            slant: Interval(configuration.lowerSlant, configuration.upperSlant),
            depth: 0
        )]
        var processedCellCount = 0
        while let cell = cells.popLast() {
            processedCellCount += 1
            guard processedCellCount <= maximumCellCount else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: Double(processedCellCount),
                    tolerance: tolerance,
                    message: "Cone-torus generator tangency certification exceeded its cell limit."
                )
            }
            let values = implicitIntervals(
                angle: cell.angle,
                slant: cell.slant,
                configuration: configuration
            )
            if values.implicit.containsZero == false
                || values.slantDerivative.containsZero == false {
                continue
            }
            guard cell.depth < maximumDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .unsupportedCapability,
                    residual: max(cell.angle.width, cell.slant.width),
                    tolerance: tolerance,
                    message: "General cone-torus generator tangency or unresolved root merge is outside the regular exact tracing envelope."
                )
            }
            let normalizedAngleWidth = cell.angle.width / (2.0 * Double.pi)
            let normalizedSlantWidth = cell.slant.width
                / (configuration.upperSlant - configuration.lowerSlant)
            if normalizedAngleWidth >= normalizedSlantWidth {
                let middle = cell.angle.midpoint
                cells.append(Cell(
                    angle: Interval(middle, cell.angle.upper),
                    slant: cell.slant,
                    depth: cell.depth + 1
                ))
                cells.append(Cell(
                    angle: Interval(cell.angle.lower, middle),
                    slant: cell.slant,
                    depth: cell.depth + 1
                ))
            } else {
                let middle = cell.slant.midpoint
                cells.append(Cell(
                    angle: cell.angle,
                    slant: Interval(middle, cell.slant.upper),
                    depth: cell.depth + 1
                ))
                cells.append(Cell(
                    angle: cell.angle,
                    slant: Interval(cell.slant.lower, middle),
                    depth: cell.depth + 1
                ))
            }
        }
    }

    private func implicitIntervals(
        angle: Interval,
        slant: Interval,
        configuration: Configuration
    ) -> (implicit: Interval, slantDerivative: Interval) {
        let cosine = cosineInterval(angle)
        let sine = sineInterval(angle)
        let direction = [
            directionInterval(
                center: configuration.centerDirection.x,
                zeroRadial: configuration.zeroRadial.x,
                quarterRadial: configuration.quarterRadial.x,
                cosine: cosine,
                sine: sine
            ),
            directionInterval(
                center: configuration.centerDirection.y,
                zeroRadial: configuration.zeroRadial.y,
                quarterRadial: configuration.quarterRadial.y,
                cosine: cosine,
                sine: sine
            ),
            directionInterval(
                center: configuration.centerDirection.z,
                zeroRadial: configuration.zeroRadial.z,
                quarterRadial: configuration.quarterRadial.z,
                cosine: cosine,
                sine: sine
            ),
        ]
        let centerOffset = configuration.cone.apex - configuration.torus.center
        let offset = [centerOffset.x, centerOffset.y, centerOffset.z]
        let coordinates = direction.indices.map { index in
            Interval.constant(offset[index]).adding(
                direction[index].multiplied(by: slant)
            )
        }
        let squaredLength = coordinates.reduce(Interval.constant(0.0)) {
            $0.adding($1.squared())
        }
        let axialDistance = dotInterval(coordinates, configuration.torus.axis)
        let generatorCoordinate = dotInterval(coordinates, direction)
        let axialDirection = dotInterval(direction, configuration.torus.axis)
        let radiusDifference = configuration.torus.majorRadius
            * configuration.torus.majorRadius
            - configuration.torus.minorRadius
                * configuration.torus.minorRadius
        let q = squaredLength.adding(.constant(radiusDifference))
        let radialSquared = squaredLength.subtracting(axialDistance.squared())
        let majorFactor = 4.0 * configuration.torus.majorRadius
            * configuration.torus.majorRadius
        let implicit = q.squared().subtracting(
            radialSquared.scaled(by: majorFactor)
        )
        let slantDerivative = q.multiplied(by: generatorCoordinate)
            .scaled(by: 4.0)
            .subtracting(
                generatorCoordinate.subtracting(
                    axialDistance.multiplied(by: axialDirection)
                ).scaled(by: 2.0 * majorFactor)
            )
        return (implicit, slantDerivative)
    }

    private func directionInterval(
        center: Double,
        zeroRadial: Double,
        quarterRadial: Double,
        cosine: Interval,
        sine: Interval
    ) -> Interval {
        Interval.constant(center)
            .adding(cosine.scaled(by: zeroRadial))
            .adding(sine.scaled(by: quarterRadial))
    }

    private func dotInterval(
        _ values: [Interval],
        _ direction: Vector3D
    ) -> Interval {
        values[0].scaled(by: direction.x)
            .adding(values[1].scaled(by: direction.y))
            .adding(values[2].scaled(by: direction.z))
    }

    private func dotInterval(
        _ first: [Interval],
        _ second: [Interval]
    ) -> Interval {
        first.indices.reduce(Interval.constant(0.0)) { result, index in
            result.adding(first[index].multiplied(by: second[index]))
        }
    }

    private func verifiedRoots(
        angle: Double,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let solver = try RealPolynomialRootSolver(
            rootTolerance: max(
                tolerance.distance * 0.001,
                Double.ulpOfOne * configuration.characteristicLength * 64.0
            ),
            residualTolerance: max(
                tolerance.angle * 0.001,
                Double.ulpOfOne * 64.0
            )
        )
        let coefficients = configuration.coefficients(at: angle)
        var roots: [Double] = []
        for candidate in try solver.realRoots(coefficients: coefficients) {
            guard candidate >= configuration.lowerSlant - tolerance.distance,
                  candidate <= configuration.upperSlant + tolerance.distance else {
                continue
            }
            let root = refinedRoot(
                candidate,
                coefficients: coefficients,
                lower: configuration.lowerSlant,
                upper: configuration.upperSlant,
                tolerance: tolerance
            )
            let derivative = polynomialDerivative(coefficients, at: root)
            let derivativeThreshold = max(
                tolerance.angle * pow(configuration.characteristicLength, 3.0),
                Double.ulpOfOne * pow(configuration.characteristicLength, 3.0) * 256.0
            )
            guard abs(derivative) > derivativeThreshold else {
                throw KernelError(
                    phase: .geometry,
                    code: .unsupportedCapability,
                    residual: abs(derivative),
                    tolerance: tolerance,
                    message: "General cone-torus tracing encountered a generator-tangent root."
                )
            }
            guard abs(root) > tolerance.distance * 8.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .unsupportedCapability,
                    residual: abs(root),
                    tolerance: tolerance,
                    message: "General cone-torus intersection reaches the cone apex."
                )
            }
            let point = configuration.generatorPoint(angle: angle, slant: root)
            let projection = try configuration.torus.surface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            guard projection.residual <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: projection.residual,
                    tolerance: tolerance,
                    message: "Cone-torus quartic root failed geometric residual verification."
                )
            }
            if roots.last.map({ abs($0 - root) <= tolerance.distance }) != true {
                roots.append(root)
            }
        }
        return roots.sorted()
    }

    private func refinedRoot(
        _ initial: Double,
        coefficients: [Double],
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        var value = min(max(initial, lower), upper)
        for _ in 0..<12 {
            let residual = polynomial(coefficients, at: value)
            let derivative = polynomialDerivative(coefficients, at: value)
            guard derivative.isFinite,
                  abs(derivative) > Double.ulpOfOne else {
                break
            }
            let next = min(max(value - residual / derivative, lower), upper)
            if abs(next - value) <= tolerance.distance * 0.001 {
                return next
            }
            value = next
        }
        return value
    }

    private func polynomial(_ coefficients: [Double], at value: Double) -> Double {
        coefficients.reversed().reduce(0.0) { $0 * value + $1 }
    }

    private func polynomialDerivative(
        _ coefficients: [Double],
        at value: Double
    ) -> Double {
        guard coefficients.count > 1 else { return 0.0 }
        return (1..<coefficients.count).reversed().reduce(0.0) { partial, index in
            partial * value + coefficients[index] * Double(index)
        }
    }

    private func rejectApexContact(
        cone: Cone,
        torus: Torus,
        tolerance: ModelingTolerance
    ) throws {
        let offset = cone.apex - torus.center
        let axial = offset.dot(torus.axis)
        let radialSquared = max(0.0, offset.dot(offset) - axial * axial)
        let meridianDistance = hypot(sqrt(radialSquared) - torus.majorRadius, axial)
        let residual = abs(meridianDistance - torus.minorRadius)
        guard residual > tolerance.distance * 8.0 else {
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                residual: residual,
                tolerance: tolerance,
                message: "General cone-torus intersection reaches the cone apex."
            )
        }
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
        let candidate = value + firstIndex * period
        return candidate <= interval.upper
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

    private func canonicalTorus(
        _ torus: CanonicalAnalyticSurface.Torus,
        tolerance: ModelingTolerance
    ) throws -> Torus {
        var axis = try torus.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) {
            axis = -axis
        }
        return Torus(
            center: torus.center,
            axis: axis,
            majorRadius: torus.majorRadius,
            minorRadius: torus.minorRadius
        )
    }

    private func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }
}
