import Foundation
import CADCore

struct GeneralTorusCylinderSurfaceIntersector {
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

    private struct Cylinder {
        let origin: Point3D
        let axis: Vector3D
        let radius: Double

        var surface: Surface3D {
            .analytic(.cylinder(origin: origin, axis: axis, radius: radius))
        }
    }

    private struct Configuration {
        let torus: Torus
        let cylinder: Cylinder
        let zeroRadial: Vector3D
        let quarterRadial: Vector3D
        let lowerHeight: Double
        let upperHeight: Double
        let characteristicLength: Double

        func generatorPoint(angle: Double, height: Double) -> Point3D {
            cylinder.origin
                + zeroRadial * cos(angle)
                + quarterRadial * sin(angle)
                + cylinder.axis * height
        }

        func coefficients(at angle: Double) -> [Double] {
            let point = generatorPoint(angle: angle, height: 0.0)
            let offset = point - torus.center
            let pointSquared = offset.dot(offset)
            let pointDirection = offset.dot(cylinder.axis)
            let axialPoint = offset.dot(torus.axis)
            let axialDirection = cylinder.axis.dot(torus.axis)
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
        let height: Interval
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
        torus: CanonicalAnalyticSurface.Torus,
        cylinder: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        guard AnalyticAxisRelation.areParallel(
            torus.axis,
            cylinder.axis,
            tolerance: tolerance
        ) == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "General torus-cylinder intersection requires non-parallel axes."
            )
        }
        let configuration = try makeConfiguration(
            torus: canonicalTorus(torus, tolerance: tolerance),
            cylinder: canonicalCylinder(cylinder, tolerance: tolerance),
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
                            message: "Certified torus-cylinder generator root count changed during tracing."
                        )
                    }
                    return configuration.generatorPoint(
                        angle: angle,
                        height: roots[branchIndex]
                    )
                }
            )
        }
    }

    private func makeConfiguration(
        torus: Torus,
        cylinder: Cylinder,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        let surface = cylinder.surface
        let zeroPoint = try surface.point(u: 0.0, v: 0.0, tolerance: tolerance)
        let quarterPoint = try surface.point(
            u: Double.pi * 0.5,
            v: 0.0,
            tolerance: tolerance
        )
        let outerRadius = torus.majorRadius + torus.minorRadius
        let centerHeight = (torus.center - cylinder.origin).dot(cylinder.axis)
        let margin = tolerance.distance * 16.0
        return Configuration(
            torus: torus,
            cylinder: cylinder,
            zeroRadial: zeroPoint - cylinder.origin,
            quarterRadial: quarterPoint - cylinder.origin,
            lowerHeight: centerHeight - outerRadius - margin,
            upperHeight: centerHeight + outerRadius + margin,
            characteristicLength: max(
                outerRadius,
                cylinder.radius,
                (torus.center - cylinder.origin).length,
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
            max(options.maximumSeedCount * 16, 4_096),
            65_536
        )
        var cells = [Cell(
            angle: Interval(0.0, 2.0 * Double.pi),
            height: Interval(configuration.lowerHeight, configuration.upperHeight),
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
                    message: "Torus-cylinder generator tangency certification exceeded its cell limit."
                )
            }
            let values = implicitIntervals(
                angle: cell.angle,
                height: cell.height,
                configuration: configuration
            )
            if values.implicit.containsZero == false
                || values.heightDerivative.containsZero == false {
                continue
            }
            guard cell.depth < maximumDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: max(cell.angle.width, cell.height.width),
                    tolerance: tolerance,
                    message: "Non-parallel torus-cylinder subdivision exhausted its budget before certifying a generator tangency or root merge."
                )
            }
            let normalizedAngleWidth = cell.angle.width / (2.0 * Double.pi)
            let normalizedHeightWidth = cell.height.width
                / (configuration.upperHeight - configuration.lowerHeight)
            if normalizedAngleWidth >= normalizedHeightWidth {
                let middle = cell.angle.midpoint
                cells.append(Cell(
                    angle: Interval(middle, cell.angle.upper),
                    height: cell.height,
                    depth: cell.depth + 1
                ))
                cells.append(Cell(
                    angle: Interval(cell.angle.lower, middle),
                    height: cell.height,
                    depth: cell.depth + 1
                ))
            } else {
                let middle = cell.height.midpoint
                cells.append(Cell(
                    angle: cell.angle,
                    height: Interval(middle, cell.height.upper),
                    depth: cell.depth + 1
                ))
                cells.append(Cell(
                    angle: cell.angle,
                    height: Interval(cell.height.lower, middle),
                    depth: cell.depth + 1
                ))
            }
        }
    }

    private func implicitIntervals(
        angle: Interval,
        height: Interval,
        configuration: Configuration
    ) -> (implicit: Interval, heightDerivative: Interval) {
        let cosine = cosineInterval(angle)
        let sine = sineInterval(angle)
        let centerOffset = configuration.cylinder.origin - configuration.torus.center
        let x = [
            coordinateInterval(
                center: centerOffset.x,
                zeroRadial: configuration.zeroRadial.x,
                quarterRadial: configuration.quarterRadial.x,
                axis: configuration.cylinder.axis.x,
                cosine: cosine,
                sine: sine,
                height: height
            ),
            coordinateInterval(
                center: centerOffset.y,
                zeroRadial: configuration.zeroRadial.y,
                quarterRadial: configuration.quarterRadial.y,
                axis: configuration.cylinder.axis.y,
                cosine: cosine,
                sine: sine,
                height: height
            ),
            coordinateInterval(
                center: centerOffset.z,
                zeroRadial: configuration.zeroRadial.z,
                quarterRadial: configuration.quarterRadial.z,
                axis: configuration.cylinder.axis.z,
                cosine: cosine,
                sine: sine,
                height: height
            ),
        ]
        let squaredLength = x.reduce(Interval.constant(0.0)) {
            $0.adding($1.squared())
        }
        let axialDistance = dotInterval(x, configuration.torus.axis)
        let generatorCoordinate = dotInterval(x, configuration.cylinder.axis)
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
        let axialDirection = configuration.torus.axis.dot(
            configuration.cylinder.axis
        )
        let heightDerivative = q.multiplied(by: generatorCoordinate)
            .scaled(by: 4.0)
            .subtracting(
                generatorCoordinate.subtracting(
                    axialDistance.scaled(by: axialDirection)
                ).scaled(by: 2.0 * majorFactor)
            )
        return (implicit, heightDerivative)
    }

    private func coordinateInterval(
        center: Double,
        zeroRadial: Double,
        quarterRadial: Double,
        axis: Double,
        cosine: Interval,
        sine: Interval,
        height: Interval
    ) -> Interval {
        Interval.constant(center)
            .adding(cosine.scaled(by: zeroRadial))
            .adding(sine.scaled(by: quarterRadial))
            .adding(height.scaled(by: axis))
    }

    private func dotInterval(
        _ values: [Interval],
        _ direction: Vector3D
    ) -> Interval {
        values[0].scaled(by: direction.x)
            .adding(values[1].scaled(by: direction.y))
            .adding(values[2].scaled(by: direction.z))
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
            guard candidate >= configuration.lowerHeight - tolerance.distance,
                  candidate <= configuration.upperHeight + tolerance.distance else {
                continue
            }
            let root = refinedRoot(
                candidate,
                coefficients: coefficients,
                lower: configuration.lowerHeight,
                upper: configuration.upperHeight,
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
                    code: .singularSystem,
                    residual: abs(derivative),
                    tolerance: tolerance,
                    message: "Non-parallel torus-cylinder tracing encountered a rank-deficient generator-tangent root."
                )
            }
            let point = configuration.generatorPoint(angle: angle, height: root)
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
                    message: "Torus-cylinder quartic root failed geometric residual verification."
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
}
