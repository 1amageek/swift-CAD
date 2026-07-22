import Foundation
import CADCore

struct GeneralTorusTorusSurfaceIntersector {
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
        let parameterized: Torus
        let reference: Torus
        let zeroRadial: Vector3D
        let quarterRadial: Vector3D
        let characteristicLength: Double

        func radial(at angle: Double) -> Vector3D {
            zeroRadial * cos(angle) + quarterRadial * sin(angle)
        }

        func meridianCurve(at angle: Double) -> Curve3D {
            let radial = radial(at: angle)
            return .analytic(.ellipse(
                center: parameterized.center + radial * parameterized.majorRadius,
                normal: radial.cross(parameterized.axis),
                majorAxis: radial,
                majorRadius: parameterized.minorRadius,
                minorRadius: parameterized.minorRadius
            ))
        }

        func point(majorAngle: Double, minorAngle: Double) -> Point3D {
            let radial = radial(at: majorAngle)
            return parameterized.center
                + radial * (
                    parameterized.majorRadius
                        + parameterized.minorRadius * cos(minorAngle)
                )
                + parameterized.axis
                    * (parameterized.minorRadius * sin(minorAngle))
        }
    }

    private struct Cell {
        let majorAngle: Interval
        let minorAngle: Interval
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

    private struct RootAssignment {
        let values: [Double]
        let candidateIndices: [Int]
        let cost: Double
        let secondCost: Double

        var maximumMovement: Double
    }

    private struct RootTrace {
        let parameters: [Double]
        let valuesByBranch: [[Double]]
        let permutation: [Int]

        func referenceValue(branch: Int, at parameter: Double) -> Double {
            if parameter <= parameters[0] {
                return valuesByBranch[branch][0]
            }
            if parameter >= parameters[parameters.count - 1] {
                return valuesByBranch[branch][parameters.count - 1]
            }
            var lower = 0
            var upper = parameters.count - 1
            while upper - lower > 1 {
                let middle = (lower + upper) / 2
                if parameters[middle] <= parameter {
                    lower = middle
                } else {
                    upper = middle
                }
            }
            let span = parameters[upper] - parameters[lower]
            let fraction = span > 0.0
                ? (parameter - parameters[lower]) / span
                : 0.0
            let lowerValue = valuesByBranch[branch][lower]
            let upperValue = valuesByBranch[branch][upper]
            return lowerValue + (upperValue - lowerValue) * fraction
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
        let tori = try [
            canonicalTorus(first, tolerance: tolerance),
            canonicalTorus(second, tolerance: tolerance),
        ].sorted { torusKey($0).lexicographicallyPrecedes(torusKey($1)) }
        let configurations = try [
            makeConfiguration(
                parameterized: tori[0],
                reference: tori[1],
                tolerance: tolerance
            ),
            makeConfiguration(
                parameterized: tori[1],
                reference: tori[0],
                tolerance: tolerance
            ),
        ]

        var recoverableErrors: [KernelError] = []
        for configuration in configurations {
            do {
                try certifyConstantSimpleMeridianRoots(
                    configuration: configuration,
                    options: options,
                    tolerance: tolerance
                )
                let initialRoots = try verifiedRoots(
                    majorAngle: 0.0,
                    configuration: configuration,
                    options: options,
                    tolerance: tolerance
                )
                guard initialRoots.isEmpty == false else {
                    return []
                }
                let trace = try makeRootTrace(
                    initialRoots: initialRoots,
                    configuration: configuration,
                    options: options,
                    tolerance: tolerance
                )
                return try makeIntersections(
                    trace: trace,
                    configuration: configuration,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    options: options,
                    tolerance: tolerance
                )
            } catch let error as KernelError
                where error.code == .resourceLimitExceeded
                    || error.code == .singularSystem {
                recoverableErrors.append(error)
            }
        }
        if let error = recoverableErrors.min(by: {
            ($0.residual ?? .infinity) < ($1.residual ?? .infinity)
        }) {
            throw error
        }
        throw KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: "General torus-torus intersection exhausted both certified meridian-quartic parameterizations."
        )
    }

    private func makeConfiguration(
        parameterized: Torus,
        reference: Torus,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        let basis = try analyticOrthonormalBasis(
            parameterized.axis,
            tolerance: tolerance
        )
        return Configuration(
            parameterized: parameterized,
            reference: reference,
            zeroRadial: basis.u,
            quarterRadial: basis.v,
            characteristicLength: max(
                parameterized.majorRadius + parameterized.minorRadius,
                reference.majorRadius + reference.minorRadius,
                (parameterized.center - reference.center).length,
                1.0
            )
        )
    }

    private func certifyConstantSimpleMeridianRoots(
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws {
        let maximumDepth = min(options.maximumSubdivisionDepth + 16, 24)
        let maximumCellCount = min(
            max(options.maximumSeedCount * 64, 16_384),
            65_536
        )
        let period = 2.0 * Double.pi
        var cells = [Cell(
            majorAngle: Interval(0.0, period),
            minorAngle: Interval(0.0, period),
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
                    message: "Torus-torus meridian tangency certification exceeded its cell limit."
                )
            }
            let values = implicitIntervals(
                majorAngle: cell.majorAngle,
                minorAngle: cell.minorAngle,
                configuration: configuration
            )
            if values.implicit.containsZero == false
                || values.minorDerivative.containsZero == false {
                continue
            }
            guard cell.depth < maximumDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: max(
                        cell.majorAngle.width,
                        cell.minorAngle.width
                    ),
                    tolerance: tolerance,
                    message: "General torus-torus subdivision exhausted its budget before certifying a meridian tangency or root merge."
                )
            }
            if cell.majorAngle.width >= cell.minorAngle.width {
                let middle = cell.majorAngle.midpoint
                cells.append(Cell(
                    majorAngle: Interval(middle, cell.majorAngle.upper),
                    minorAngle: cell.minorAngle,
                    depth: cell.depth + 1
                ))
                cells.append(Cell(
                    majorAngle: Interval(cell.majorAngle.lower, middle),
                    minorAngle: cell.minorAngle,
                    depth: cell.depth + 1
                ))
            } else {
                let middle = cell.minorAngle.midpoint
                cells.append(Cell(
                    majorAngle: cell.majorAngle,
                    minorAngle: Interval(middle, cell.minorAngle.upper),
                    depth: cell.depth + 1
                ))
                cells.append(Cell(
                    majorAngle: cell.majorAngle,
                    minorAngle: Interval(cell.minorAngle.lower, middle),
                    depth: cell.depth + 1
                ))
            }
        }
    }

    private func implicitIntervals(
        majorAngle: Interval,
        minorAngle: Interval,
        configuration: Configuration
    ) -> (implicit: Interval, minorDerivative: Interval) {
        let majorCosine = cosineInterval(majorAngle)
        let majorSine = sineInterval(majorAngle)
        let minorCosine = cosineInterval(minorAngle)
        let minorSine = sineInterval(minorAngle)
        let radial = [
            radialInterval(
                zero: configuration.zeroRadial.x,
                quarter: configuration.quarterRadial.x,
                cosine: majorCosine,
                sine: majorSine
            ),
            radialInterval(
                zero: configuration.zeroRadial.y,
                quarter: configuration.quarterRadial.y,
                cosine: majorCosine,
                sine: majorSine
            ),
            radialInterval(
                zero: configuration.zeroRadial.z,
                quarter: configuration.quarterRadial.z,
                cosine: majorCosine,
                sine: majorSine
            ),
        ]
        let radialScale = Interval.constant(configuration.parameterized.majorRadius)
            .adding(
                minorCosine.scaled(
                    by: configuration.parameterized.minorRadius
                )
            )
        let axialScale = minorSine.scaled(
            by: configuration.parameterized.minorRadius
        )
        let centerOffset = configuration.parameterized.center
            - configuration.reference.center
        let offset = [centerOffset.x, centerOffset.y, centerOffset.z]
        let coordinates = radial.indices.map { index in
            Interval.constant(offset[index])
                .adding(radial[index].multiplied(by: radialScale))
                .adding(
                    axialScale.scaled(
                        by: axisComponent(
                            configuration.parameterized.axis,
                            at: index
                        )
                    )
                )
        }
        let radialDerivativeScale = minorSine.scaled(
            by: -configuration.parameterized.minorRadius
        )
        let axialDerivativeScale = minorCosine.scaled(
            by: configuration.parameterized.minorRadius
        )
        let derivatives = radial.indices.map { index in
            radial[index].multiplied(by: radialDerivativeScale)
                .adding(
                    axialDerivativeScale.scaled(
                        by: axisComponent(
                            configuration.parameterized.axis,
                            at: index
                        )
                    )
                )
        }
        let squaredLength = coordinates.reduce(Interval.constant(0.0)) {
            $0.adding($1.squared())
        }
        let axialDistance = dotInterval(
            coordinates,
            configuration.reference.axis
        )
        let pointDerivative = dotInterval(coordinates, derivatives)
        let axialDerivative = dotInterval(
            derivatives,
            configuration.reference.axis
        )
        let radiusDifference = configuration.reference.majorRadius
            * configuration.reference.majorRadius
            - configuration.reference.minorRadius
                * configuration.reference.minorRadius
        let q = squaredLength.adding(.constant(radiusDifference))
        let radialSquared = squaredLength.subtracting(axialDistance.squared())
        let majorFactor = 4.0 * configuration.reference.majorRadius
            * configuration.reference.majorRadius
        let implicit = q.squared().subtracting(
            radialSquared.scaled(by: majorFactor)
        )
        let minorDerivative = q.multiplied(by: pointDerivative)
            .scaled(by: 4.0)
            .subtracting(
                pointDerivative.subtracting(
                    axialDistance.multiplied(by: axialDerivative)
                ).scaled(by: 2.0 * majorFactor)
            )
        return (implicit, minorDerivative)
    }

    private func makeRootTrace(
        initialRoots: [Double],
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> RootTrace {
        let period = 2.0 * Double.pi
        var parameters = [0.0]
        var valuesByBranch = initialRoots.map { [$0] }
        var finalCandidateIndices = Array(initialRoots.indices)
        var acceptedSegmentCount = 0

        func appendInterval(
            lowerParameter: Double,
            lowerValues: [Double],
            upperParameter: Double,
            depth: Int
        ) throws -> [Double] {
            let roots = try verifiedRoots(
                majorAngle: upperParameter,
                configuration: configuration,
                options: options,
                tolerance: tolerance
            )
            guard roots.count == initialRoots.count else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: Double(abs(roots.count - initialRoots.count)),
                    tolerance: tolerance,
                    message: "Certified torus-torus meridian root count changed during tracing."
                )
            }
            let assignment = bestAssignment(
                previous: lowerValues,
                candidates: roots,
                period: period
            )
            let ambiguityTolerance = max(
                tolerance.angle * tolerance.angle * 64.0,
                Double.ulpOfOne * 1_024.0
            )
            let assignmentIsStable = assignment.maximumMovement < Double.pi * 0.5
                && (assignment.secondCost - assignment.cost > ambiguityTolerance
                    || assignment.secondCost.isInfinite)
            if assignmentIsStable {
                acceptedSegmentCount += 1
                guard acceptedSegmentCount <= options.maximumSeedCount else {
                    throw KernelError(
                        phase: .geometry,
                        code: .resourceLimitExceeded,
                        residual: Double(acceptedSegmentCount),
                        tolerance: tolerance,
                        message: "Torus-torus periodic root tracing exceeded its segment limit."
                    )
                }
                parameters.append(upperParameter)
                for branch in valuesByBranch.indices {
                    valuesByBranch[branch].append(assignment.values[branch])
                }
                if abs(upperParameter - period) <= tolerance.angle {
                    finalCandidateIndices = assignment.candidateIndices
                }
                return assignment.values
            }
            guard depth < min(options.maximumSubdivisionDepth + 8, 24) else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: assignment.maximumMovement,
                    tolerance: tolerance,
                    message: "Torus-torus periodic root assignment remained ambiguous after adaptive continuation."
                )
            }
            let middle = lowerParameter + (upperParameter - lowerParameter) * 0.5
            let middleValues = try appendInterval(
                lowerParameter: lowerParameter,
                lowerValues: lowerValues,
                upperParameter: middle,
                depth: depth + 1
            )
            return try appendInterval(
                lowerParameter: middle,
                lowerValues: middleValues,
                upperParameter: upperParameter,
                depth: depth + 1
            )
        }

        let initialSegmentCount = 32
        var lowerParameter = 0.0
        var lowerValues = initialRoots
        for index in 1...initialSegmentCount {
            let upperParameter = period * Double(index)
                / Double(initialSegmentCount)
            lowerValues = try appendInterval(
                lowerParameter: lowerParameter,
                lowerValues: lowerValues,
                upperParameter: upperParameter,
                depth: 0
            )
            lowerParameter = upperParameter
        }
        guard Set(finalCandidateIndices).count == initialRoots.count else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "Torus-torus periodic continuation did not produce a root permutation."
            )
        }
        return RootTrace(
            parameters: parameters,
            valuesByBranch: valuesByBranch,
            permutation: finalCandidateIndices
        )
    }

    private func makeIntersections(
        trace: RootTrace,
        configuration: Configuration,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let period = 2.0 * Double.pi
        let cycles = try permutationCycles(
            trace.permutation,
            tolerance: tolerance
        )
        let builder = SurfaceIntersectionSplineBuilder(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )
        return try cycles.map { cycle in
            let upper = period * Double(cycle.count)
            let breakCount = 32 * cycle.count
            let breaks = (0...breakCount).map {
                upper * Double($0) / Double(breakCount)
            }
            return try builder.intersection(
                parameterRange: 0.0...upper,
                initialBreaks: breaks,
                kind: .transverse,
                pointAt: { parameter in
                    if abs(parameter - upper) <= tolerance.angle {
                        return configuration.point(
                            majorAngle: 0.0,
                            minorAngle: trace.valuesByBranch[cycle[0]][0]
                        )
                    }
                    let cycleIndex = min(
                        Int(floor(max(parameter, 0.0) / period)),
                        cycle.count - 1
                    )
                    let localParameter = parameter - Double(cycleIndex) * period
                    let branch = cycle[cycleIndex]
                    let roots = try verifiedRoots(
                        majorAngle: localParameter,
                        configuration: configuration,
                        options: options,
                        tolerance: tolerance
                    )
                    let reference = trace.referenceValue(
                        branch: branch,
                        at: localParameter
                    )
                    let minorAngle = try selectedRoot(
                        candidates: roots,
                        reference: reference,
                        period: period,
                        tolerance: tolerance
                    )
                    return configuration.point(
                        majorAngle: localParameter,
                        minorAngle: minorAngle
                    )
                }
            )
        }
    }

    private func verifiedRoots(
        majorAngle: Double,
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let intersector = DefaultCurveSurfaceIntersector()
        let intersections = try intersector.intersections(
            curve: configuration.meridianCurve(at: majorAngle),
            surface: configuration.reference.surface,
            options: CurveSurfaceIntersectionOptions(
                maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                maximumIterations: options.maximumIterations,
                maximumCandidateCount: options.maximumSeedCount
            ),
            tolerance: tolerance
        )
        var roots: [Double] = []
        for intersection in intersections {
            guard intersection.kind == .transverse else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: intersection.residual,
                    tolerance: tolerance,
                    message: "General torus-torus tracing encountered a rank-deficient meridian-tangent root."
                )
            }
            let root = normalizedAngle(intersection.curveParameter)
            let point = configuration.point(
                majorAngle: majorAngle,
                minorAngle: root
            )
            let residual = max(
                intersection.residual,
                (point - intersection.point).length
            )
            guard residual <= tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Torus-torus meridian quartic root failed geometric residual verification."
                )
            }
            if roots.allSatisfy({
                periodicDistance($0, root, period: 2.0 * Double.pi)
                    > tolerance.angle
            }) {
                roots.append(root)
            }
        }
        return roots.sorted()
    }

    private func bestAssignment(
        previous: [Double],
        candidates: [Double],
        period: Double
    ) -> RootAssignment {
        var bestValues: [Double] = []
        var bestIndices: [Int] = []
        var bestCost = Double.infinity
        var secondCost = Double.infinity
        var bestMaximumMovement = Double.infinity

        func search(
            branch: Int,
            used: Set<Int>,
            values: [Double],
            indices: [Int],
            cost: Double,
            maximumMovement: Double
        ) {
            if branch == previous.count {
                if cost < bestCost {
                    secondCost = bestCost
                    bestCost = cost
                    bestValues = values
                    bestIndices = indices
                    bestMaximumMovement = maximumMovement
                } else if cost < secondCost {
                    secondCost = cost
                }
                return
            }
            for candidateIndex in candidates.indices where used.contains(candidateIndex) == false {
                let candidate = liftedPeriodicValue(
                    candidates[candidateIndex],
                    near: previous[branch],
                    period: period
                )
                let movement = abs(candidate - previous[branch])
                let nextCost = cost + movement * movement
                guard nextCost < secondCost else { continue }
                var nextUsed = used
                nextUsed.insert(candidateIndex)
                search(
                    branch: branch + 1,
                    used: nextUsed,
                    values: values + [candidate],
                    indices: indices + [candidateIndex],
                    cost: nextCost,
                    maximumMovement: max(maximumMovement, movement)
                )
            }
        }

        search(
            branch: 0,
            used: [],
            values: [],
            indices: [],
            cost: 0.0,
            maximumMovement: 0.0
        )
        return RootAssignment(
            values: bestValues,
            candidateIndices: bestIndices,
            cost: bestCost,
            secondCost: secondCost,
            maximumMovement: bestMaximumMovement
        )
    }

    private func selectedRoot(
        candidates: [Double],
        reference: Double,
        period: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let ranked = candidates.map {
            liftedPeriodicValue($0, near: reference, period: period)
        }.sorted { abs($0 - reference) < abs($1 - reference) }
        guard let selected = ranked.first else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Torus-torus branch evaluation produced no meridian root."
            )
        }
        if ranked.count > 1 {
            let firstDistance = abs(ranked[0] - reference)
            let secondDistance = abs(ranked[1] - reference)
            guard secondDistance - firstDistance > tolerance.angle * 8.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: secondDistance - firstDistance,
                    tolerance: tolerance,
                    message: "Torus-torus branch evaluation found an ambiguous periodic root assignment."
                )
            }
        }
        return selected
    }

    private func permutationCycles(
        _ permutation: [Int],
        tolerance: ModelingTolerance
    ) throws -> [[Int]] {
        var visited = Set<Int>()
        var cycles: [[Int]] = []
        for start in permutation.indices where visited.contains(start) == false {
            var cycle: [Int] = []
            var current = start
            while visited.contains(current) == false {
                guard permutation.indices.contains(current) else {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularSystem,
                        tolerance: tolerance,
                        message: "Torus-torus root permutation contains an invalid branch index."
                    )
                }
                visited.insert(current)
                cycle.append(current)
                current = permutation[current]
            }
            guard current == start else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    tolerance: tolerance,
                    message: "Torus-torus root permutation does not decompose into closed cycles."
                )
            }
            cycles.append(cycle)
        }
        return cycles
    }

    private func radialInterval(
        zero: Double,
        quarter: Double,
        cosine: Interval,
        sine: Interval
    ) -> Interval {
        cosine.scaled(by: zero).adding(sine.scaled(by: quarter))
    }

    private func dotInterval(
        _ first: [Interval],
        _ second: [Interval]
    ) -> Interval {
        first.indices.reduce(Interval.constant(0.0)) { result, index in
            result.adding(first[index].multiplied(by: second[index]))
        }
    }

    private func dotInterval(
        _ values: [Interval],
        _ direction: Vector3D
    ) -> Interval {
        values[0].scaled(by: direction.x)
            .adding(values[1].scaled(by: direction.y))
            .adding(values[2].scaled(by: direction.z))
    }

    private func axisComponent(_ axis: Vector3D, at index: Int) -> Double {
        switch index {
        case 0: axis.x
        case 1: axis.y
        default: axis.z
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

    private func liftedPeriodicValue(
        _ value: Double,
        near reference: Double,
        period: Double
    ) -> Double {
        value + round((reference - value) / period) * period
    }

    private func periodicDistance(
        _ first: Double,
        _ second: Double,
        period: Double
    ) -> Double {
        abs(liftedPeriodicValue(first, near: second, period: period) - second)
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        let period = 2.0 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
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

    private func torusKey(_ torus: Torus) -> [Double] {
        [
            torus.center.x,
            torus.center.y,
            torus.center.z,
            torus.axis.x,
            torus.axis.y,
            torus.axis.z,
            torus.majorRadius,
            torus.minorRadius,
        ]
    }

    private func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }
}
