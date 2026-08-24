import CADCore
import Foundation

public struct DefaultCurveArcLengthResolver: CurveArcLengthResolving {
    private struct Cell: Sendable {
        let interval: ScalarInterval
        let lowerBound: Double
        let upperBound: Double
        let depth: Int
        let bezierPatch: RationalBezierCurvePatch3D?

        var gap: Double {
            upperBound - lowerBound
        }
    }

    private struct CellHeap {
        private var storage: [Cell] = []

        var count: Int {
            storage.count
        }

        var cells: [Cell] {
            storage
        }

        mutating func insert(_ cell: Cell) {
            storage.append(cell)
            var child = storage.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard storage[child].gap > storage[parent].gap else { break }
                storage.swapAt(child, parent)
                child = parent
            }
        }

        mutating func removeMaximum() -> Cell? {
            guard storage.isEmpty == false else { return nil }
            if storage.count == 1 {
                return storage.removeLast()
            }
            let result = storage[0]
            storage[0] = storage.removeLast()
            var parent = 0
            while true {
                let left = parent * 2 + 1
                guard left < storage.count else { break }
                let right = left + 1
                let child = (
                    right < storage.count
                        && storage[right].gap > storage[left].gap
                ) ? right : left
                guard storage[child].gap > storage[parent].gap else { break }
                storage.swapAt(parent, child)
                parent = child
            }
            return result
        }
    }

    private struct PreparedParameterization: CurveArcLengthParameterization {
        let lengthEnclosure: CurveArcLengthEnclosure
        let curve: Curve3D
        let interval: ScalarInterval
        let absoluteAccuracy: Double
        let options: CurveArcLengthOptions
        let tolerance: ModelingTolerance
        let cells: [Cell]?
        let resolver: DefaultCurveArcLengthResolver

        func parameterEnclosure(
            atArcLengthFraction fraction: Double
        ) throws -> CurveArcLengthParameterEnclosure {
            guard fraction.isFinite,
                  fraction >= 0.0,
                  fraction <= 1.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    residual: fraction,
                    tolerance: tolerance,
                    message: "Curve arc-length fraction must be finite and lie in the closed unit interval."
                )
            }
            if fraction == 0.0 {
                return try CurveArcLengthParameterEnclosure(
                    parameterRange: ScalarInterval(
                        lower: interval.lower,
                        upper: interval.lower
                    ),
                    spatialErrorUpperBound: 0.0
                )
            }
            if fraction == 1.0 {
                return try CurveArcLengthParameterEnclosure(
                    parameterRange: ScalarInterval(
                        lower: interval.upper,
                        upper: interval.upper
                    ),
                    spatialErrorUpperBound: 0.0
                )
            }
            guard let cells else {
                let parameter = interval.lower + interval.width * fraction
                return try CurveArcLengthParameterEnclosure(
                    parameterRange: ScalarInterval(
                        lower: parameter,
                        upper: parameter
                    ),
                    spatialErrorUpperBound: 0.0
                )
            }
            return try resolver.invertedParameterEnclosure(
                atArcLengthFraction: fraction,
                curve: curve,
                interval: interval,
                lengthEnclosure: lengthEnclosure,
                initialCells: cells,
                absoluteAccuracy: absoluteAccuracy,
                options: options,
                tolerance: tolerance
            )
        }
    }

    public init() {}

    public func enclosure(
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions = CurveArcLengthOptions(),
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthEnclosure {
        try tolerance.validate()
        let absoluteAccuracy = try options.validatedAbsoluteAccuracy(
            tolerance: tolerance
        )
        try curve.validate(tolerance: tolerance)
        guard interval.width > 0.0,
              try curve.parameterDomain.containsSpan(
                from: interval.lower,
                to: interval.upper,
                tolerance: tolerance
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Curve arc-length evaluation requires a positive interval inside the curve domain."
            )
        }
        if let exactEnclosure = try constantSpeedEnclosure(
            of: curve,
            over: interval
        ) {
            return exactEnclosure
        }
        return try certifiedPartition(
            curve: curve,
            interval: interval,
            absoluteAccuracy: absoluteAccuracy,
            options: options,
            tolerance: tolerance
        ).enclosure
    }

    public func parameterEnclosure(
        atArcLengthFraction fraction: Double,
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions = CurveArcLengthOptions(),
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthParameterEnclosure {
        let prepared = try parameterization(
            of: curve,
            over: interval,
            options: options,
            tolerance: tolerance
        )
        return try prepared.parameterEnclosure(
            atArcLengthFraction: fraction
        )
    }

    public func parameterization(
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions = CurveArcLengthOptions(),
        tolerance: ModelingTolerance
    ) throws -> any CurveArcLengthParameterization {
        try tolerance.validate()
        let absoluteAccuracy = try options.validatedAbsoluteAccuracy(
            tolerance: tolerance
        )
        try curve.validate(tolerance: tolerance)
        guard interval.width > 0.0,
              try curve.parameterDomain.containsSpan(
                from: interval.lower,
                to: interval.upper,
                tolerance: tolerance
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Curve arc-length parameterization requires a positive interval inside the curve domain."
            )
        }
        if let constantEnclosure = try constantSpeedEnclosure(
            of: curve,
            over: interval
        ) {
            return PreparedParameterization(
                lengthEnclosure: constantEnclosure,
                curve: curve,
                interval: interval,
                absoluteAccuracy: absoluteAccuracy,
                options: options,
                tolerance: tolerance,
                cells: nil,
                resolver: self
            )
        }
        // Half of the spatial budget is reserved for uncertainty in the
        // total-length target; the remaining half is resolved locally by
        // the inverse search.
        let partitionAccuracy = absoluteAccuracy * 0.5
        let tightenedOptions = CurveArcLengthOptions(
            absoluteAccuracy: partitionAccuracy,
            relativeAccuracy: min(options.relativeAccuracy, 1.0e-12),
            maximumSubdivisionDepth: options.maximumSubdivisionDepth,
            maximumIntervalCount: options.maximumIntervalCount
        )
        let partitionResult = try certifiedPartition(
            curve: curve,
            interval: interval,
            absoluteAccuracy: partitionAccuracy,
            options: tightenedOptions,
            tolerance: tolerance
        )
        return PreparedParameterization(
            lengthEnclosure: partitionResult.enclosure,
            curve: curve,
            interval: interval,
            absoluteAccuracy: absoluteAccuracy,
            options: options,
            tolerance: tolerance,
            cells: partitionResult.cells,
            resolver: self
        )
    }

    private func invertedParameterEnclosure(
        atArcLengthFraction fraction: Double,
        curve: Curve3D,
        interval: ScalarInterval,
        lengthEnclosure total: CurveArcLengthEnclosure,
        initialCells: [Cell],
        absoluteAccuracy: Double,
        options: CurveArcLengthOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthParameterEnclosure {
        let targetLower = fraction * total.lowerBound
        let targetUpper = fraction * total.upperBound
        var cells = initialCells
        var splitCount = 0
        while true {
            let candidates = candidateCellRange(
                cells: cells,
                targetLower: targetLower,
                targetUpper: targetUpper
            )
            guard let candidates,
                  let firstIndex = candidates.first,
                  let lastIndex = candidates.last else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Certified curve arc-length inversion lost the target from its cumulative length enclosure."
                )
            }
            let spatialError = cells[firstIndex...lastIndex].reduce(0.0) {
                ($0 + $1.upperBound).nextUp
            }
            let parameterRange = try ScalarInterval(
                lower: cells[firstIndex].interval.lower,
                upper: cells[lastIndex].interval.upper
            )
            if spatialError <= absoluteAccuracy {
                return try CurveArcLengthParameterEnclosure(
                    parameterRange: parameterRange,
                    spatialErrorUpperBound: spatialError
                )
            }
            guard splitCount < options.maximumIntervalCount,
                  cells.count < options.maximumIntervalCount else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: spatialError,
                    tolerance: tolerance,
                    message: "Certified curve arc-length inversion exceeded its interval budget before reaching the requested spatial error."
                )
            }
            let splitIndex = (firstIndex...lastIndex).max {
                cells[$0].upperBound < cells[$1].upperBound
            } ?? firstIndex
            let source = cells[splitIndex]
            guard source.depth < options.maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: spatialError,
                    tolerance: tolerance,
                    message: "Certified curve arc-length inversion exceeded its subdivision depth."
                )
            }
            let halves = try split(
                source,
                curve: curve,
                tolerance: tolerance
            )
            cells.replaceSubrange(
                splitIndex...splitIndex,
                with: [halves.lower, halves.upper]
            )
            splitCount += 1
        }
    }

    private func constantSpeedEnclosure(
        of curve: Curve3D,
        over interval: ScalarInterval
    ) throws -> CurveArcLengthEnclosure? {
        let parameterWidth = interval.width
        let speed: Double
        switch curve {
        case .line, .analytic(.line):
            speed = 1.0
        case let .circle(circle):
            speed = circle.radius
        case let .analytic(.circle(_, _, radius)),
             let .analytic(.arc(_, _, radius, _, _)):
            speed = radius
        case let .rigidImage(image):
            return try constantSpeedEnclosure(of: image.source, over: interval)
        case .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection, .affineImage:
            return nil
        }
        let value = speed * parameterWidth
        return try CurveArcLengthEnclosure(
            lowerBound: max(0.0, value.nextDown),
            upperBound: value.nextUp
        )
    }

    private func certifiedPartition(
        curve: Curve3D,
        interval: ScalarInterval,
        absoluteAccuracy: Double,
        options: CurveArcLengthOptions,
        tolerance: ModelingTolerance
    ) throws -> (cells: [Cell], enclosure: CurveArcLengthEnclosure) {
        let initialCells = try initialCells(
            curve: curve,
            interval: interval,
            tolerance: tolerance
        )
        guard initialCells.isEmpty == false,
              initialCells.count <= options.maximumIntervalCount else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: Double(initialCells.count),
                tolerance: tolerance,
                message: "Certified curve arc-length evaluation exceeded its initial interval budget."
            )
        }
        var lowerBound = 0.0
        var upperBound = 0.0
        var heap = CellHeap()
        for initial in initialCells {
            lowerBound = (lowerBound + initial.lowerBound).nextDown
            upperBound = (upperBound + initial.upperBound).nextUp
            heap.insert(initial)
        }
        while upperBound - lowerBound > max(
            absoluteAccuracy,
            options.relativeAccuracy * upperBound
        ) {
            guard heap.count < options.maximumIntervalCount,
                  let source = heap.removeMaximum(),
                  source.depth < options.maximumSubdivisionDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: upperBound - lowerBound,
                    tolerance: tolerance,
                    message: "Certified curve arc-length evaluation exceeded its subdivision budget before reaching the requested enclosure width."
                )
            }
            let halves = try split(
                source,
                curve: curve,
                tolerance: tolerance
            )
            lowerBound += halves.lower.lowerBound
                + halves.upper.lowerBound
                - source.lowerBound
            upperBound += halves.lower.upperBound
                + halves.upper.upperBound
                - source.upperBound
            lowerBound = max(0.0, lowerBound.nextDown)
            upperBound = max(lowerBound, upperBound.nextUp)
            heap.insert(halves.lower)
            heap.insert(halves.upper)
        }
        return (
            cells: heap.cells.sorted {
                $0.interval.lower < $1.interval.lower
            },
            enclosure: try CurveArcLengthEnclosure(
                lowerBound: lowerBound,
                upperBound: upperBound
            )
        )
    }

    private func split(
        _ source: Cell,
        curve: Curve3D,
        tolerance: ModelingTolerance
    ) throws -> (lower: Cell, upper: Cell) {
        if let patch = source.bezierPatch {
            let halves = try patch.subdivided(tolerance: tolerance)
            guard halves.count == 2 else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Rational Bezier arc-length subdivision must produce two child patches."
                )
            }
            return (
                try cell(
                    curve: curve,
                    interval: ScalarInterval(
                        lower: halves[0].lower,
                        upper: halves[0].upper
                    ),
                    depth: source.depth + 1,
                    bezierPatch: halves[0],
                    tolerance: tolerance
                ),
                try cell(
                    curve: curve,
                    interval: ScalarInterval(
                        lower: halves[1].lower,
                        upper: halves[1].upper
                    ),
                    depth: source.depth + 1,
                    bezierPatch: halves[1],
                    tolerance: tolerance
                )
            )
        }
        let middle = source.interval.midpoint
        return (
            try cell(
                curve: curve,
                interval: ScalarInterval(
                    lower: source.interval.lower,
                    upper: middle
                ),
                depth: source.depth + 1,
                bezierPatch: nil,
                tolerance: tolerance
            ),
            try cell(
                curve: curve,
                interval: ScalarInterval(
                    lower: middle,
                    upper: source.interval.upper
                ),
                depth: source.depth + 1,
                bezierPatch: nil,
                tolerance: tolerance
            )
        )
    }

    private func candidateCellRange(
        cells: [Cell],
        targetLower: Double,
        targetUpper: Double
    ) -> ClosedRange<Int>? {
        var prefixLower = 0.0
        var prefixUpper = 0.0
        var first: Int?
        var last: Int?
        for index in cells.indices {
            let endLower = prefixLower + cells[index].lowerBound
            let endUpper = prefixUpper + cells[index].upperBound
            if endUpper >= targetLower,
               prefixLower <= targetUpper {
                first = first ?? index
                last = index
            }
            prefixLower = endLower.nextDown
            prefixUpper = endUpper.nextUp
        }
        guard let first, let last else { return nil }
        return first...last
    }

    private func cell(
        curve: Curve3D,
        interval: ScalarInterval,
        depth: Int,
        bezierPatch: RationalBezierCurvePatch3D?,
        tolerance: ModelingTolerance
    ) throws -> Cell {
        let start = try curve.point(
            at: interval.lower,
            tolerance: tolerance
        )
        let end = try curve.point(
            at: interval.upper,
            tolerance: tolerance
        )
        let chord = (end - start).length
        let arcLengthUpperBound: Double
        let speedLowerBound: Double
        let secondDerivativeMagnitudeUpperBound: Double
        let thirdDerivativeBound: Double?
        if let bezierPatch {
            let derivativeBound = try RationalBezierCurveDerivativeBound(
                coordinates: [
                    bezierPatch.controlPoints.map(\.x),
                    bezierPatch.controlPoints.map(\.y),
                    bezierPatch.controlPoints.map(\.z),
                ],
                weights: bezierPatch.weights,
                parameterWidth: interval.width,
                tolerance: tolerance
            )
            secondDerivativeMagnitudeUpperBound = hypot(
                hypot(derivativeBound.second[0], derivativeBound.second[1]),
                derivativeBound.second[2]
            ).nextUp
            thirdDerivativeBound = hypot(
                hypot(derivativeBound.third[0], derivativeBound.third[1]),
                derivativeBound.third[2]
            ).nextUp
            let midpointDerivative: Vector3D
            if case let .bSpline(spline) = curve {
                midpointDerivative = try spline.parameterDerivatives(
                    at: interval.midpoint,
                    tolerance: tolerance
                ).firstDerivative
            } else {
                midpointDerivative = try curve.differentialGeometry(
                    at: interval.midpoint,
                    tolerance: tolerance
                ).firstDerivative
            }
            let derivativeRadius = (
                secondDerivativeMagnitudeUpperBound * interval.width * 0.5
            ).nextUp
            speedLowerBound = max(
                0.0,
                (midpointDerivative.length - derivativeRadius).nextDown
            )
            arcLengthUpperBound = (
                (midpointDerivative.length + derivativeRadius).nextUp
                    * interval.width
            ).nextUp
        } else {
            let bounds = try curve.tessellationIntervalBounds(
                interval,
                tolerance: tolerance
            )
            arcLengthUpperBound = bounds.arcLengthUpperBound
            speedLowerBound = bounds.speedLowerBound
            secondDerivativeMagnitudeUpperBound =
                bounds.secondDerivativeMagnitudeUpperBound
            thirdDerivativeBound = try thirdDerivativeMagnitudeUpperBound(
                curve: curve,
                interval: interval,
                tolerance: tolerance
            )
        }
        let floatingPointMargin = max(
            Double.ulpOfOne * max(chord, 1.0) * 64.0,
            chord.ulp * 8.0
        )
        var lowerBound = max(0.0, chord - floatingPointMargin)
        var upperBound = max(
            lowerBound,
            arcLengthUpperBound.nextUp
        )
        if speedLowerBound > 0.0,
           secondDerivativeMagnitudeUpperBound.isFinite,
           let thirdDerivativeBound {
            let midpointDerivative: Vector3D
            if case let .bSpline(spline) = curve {
                midpointDerivative = try spline.parameterDerivatives(
                    at: interval.midpoint,
                    tolerance: tolerance
                ).firstDerivative
            } else {
                midpointDerivative = try curve.differentialGeometry(
                    at: interval.midpoint,
                    tolerance: tolerance
                ).firstDerivative
            }
            let midpointEstimate = midpointDerivative.length * interval.width
            let speedSecondDerivativeBound = (
                secondDerivativeMagnitudeUpperBound
                    * secondDerivativeMagnitudeUpperBound
                    / speedLowerBound
                + thirdDerivativeBound
            ).nextUp
            let midpointError = (
                speedSecondDerivativeBound
                    * interval.width
                    * interval.width
                    * interval.width
                    / 24.0
            ).nextUp
            let midpointFloatingPointMargin = max(
                Double.ulpOfOne
                    * max(abs(midpointEstimate), abs(midpointError))
                    * 64.0,
                midpointEstimate.ulp * 8.0
            )
            lowerBound = max(
                lowerBound,
                midpointEstimate
                    - midpointError
                    - midpointFloatingPointMargin
            )
            upperBound = min(
                upperBound,
                midpointEstimate
                    + midpointError
                    + midpointFloatingPointMargin
            )
            upperBound = max(lowerBound, upperBound)
        }
        return Cell(
            interval: interval,
            lowerBound: lowerBound,
            upperBound: upperBound,
            depth: depth,
            bezierPatch: bezierPatch
        )
    }

    private func initialCells(
        curve: Curve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> [Cell] {
        guard case let .bSpline(spline) = curve else {
            return [try cell(
                curve: curve,
                interval: interval,
                depth: 0,
                bezierPatch: nil,
                tolerance: tolerance
            )]
        }
        let sourcePatches = try BSplineCurveBezierDecomposer().curvePatches(
            curve: spline,
            intersecting: interval,
            tolerance: tolerance
        )
        guard sourcePatches.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "B-spline arc-length interval has no rational Bezier span."
            )
        }
        return try sourcePatches.compactMap { source -> Cell? in
            let lower = max(interval.lower, source.lower)
            let upper = min(interval.upper, source.upper)
            guard upper > lower else { return nil }
            let patch = lower == source.lower && upper == source.upper
                ? source
                : try source.trimmed(
                    from: lower,
                    to: upper,
                    tolerance: tolerance
                )
            return try cell(
                curve: curve,
                interval: ScalarInterval(lower: lower, upper: upper),
                depth: 0,
                bezierPatch: patch,
                tolerance: tolerance
            )
        }
    }

    private func thirdDerivativeMagnitudeUpperBound(
        curve: Curve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        switch curve {
        case .line, .analytic(.line), .analytic(.parabola):
            return 0.0
        case let .circle(circle):
            return circle.radius.nextUp
        case let .analytic(.circle(_, _, radius)),
             let .analytic(.arc(_, _, radius, _, _)):
            return radius.nextUp
        case let .analytic(.ellipse(_, _, _, majorRadius, minorRadius)):
            return max(majorRadius, minorRadius).nextUp
        case let .analytic(.hyperbola(hyperbola)):
            let parameter = max(abs(interval.lower), abs(interval.upper))
            let value = hypot(
                hyperbola.transverseRadius * sinh(parameter),
                hyperbola.conjugateRadius * cosh(parameter)
            )
            return value.isFinite ? value.nextUp : nil
        case let .analytic(.planeTorus(curve)):
            return try curve.spatialDifferentialMagnitudeBounds(
                fromParameter: interval.lower,
                toParameter: interval.upper,
                tolerance: tolerance
            ).third
        case let .bSpline(spline):
            let patches = try BSplineCurveBezierDecomposer().curvePatches(
                curve: spline,
                intersecting: interval,
                tolerance: tolerance
            )
            guard patches.isEmpty == false else { return nil }
            var result = 0.0
            for source in patches {
                let lower = max(interval.lower, source.lower)
                let upper = min(interval.upper, source.upper)
                guard upper > lower else { continue }
                let patch = lower == source.lower && upper == source.upper
                    ? source
                    : try source.trimmed(
                        from: lower,
                        to: upper,
                        tolerance: tolerance
                    )
                let bound = try RationalBezierCurveDerivativeBound(
                    coordinates: [
                        patch.controlPoints.map(\.x),
                        patch.controlPoints.map(\.y),
                        patch.controlPoints.map(\.z),
                    ],
                    weights: patch.weights,
                    parameterWidth: patch.upper - patch.lower,
                    tolerance: tolerance
                )
                result = max(
                    result,
                    hypot(
                        hypot(bound.third[0], bound.third[1]),
                        bound.third[2]
                    ).nextUp
                )
            }
            return result
        case let .rigidImage(image):
            return try thirdDerivativeMagnitudeUpperBound(
                curve: image.source,
                interval: interval,
                tolerance: tolerance
            )
        case let .affineImage(image):
            guard let sourceBound = try thirdDerivativeMagnitudeUpperBound(
                curve: image.source,
                interval: interval,
                tolerance: tolerance
            ) else {
                return nil
            }
            let transformedBound = (
                sourceBound * image.transform.linearMagnitudeUpperBound
            ).nextUp
            return transformedBound.isFinite ? transformedBound : nil
        case .implicit, .surfaceLift, .certifiedIntersection:
            return nil
        }
    }
}
