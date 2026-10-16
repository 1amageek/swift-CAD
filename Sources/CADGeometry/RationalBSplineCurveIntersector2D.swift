import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

/// A unique root enclosure for two bounded rational B-spline curves in one
/// two-dimensional chart. The enclosures, rather than a refined floating-point
/// witness, are the correctness contract consumed by downstream geometry.
package struct RationalBSplineCurveIntersection2D: Sendable {
    package let firstParameterEnclosure: ScalarInterval
    package let secondParameterEnclosure: ScalarInterval
    package let pointEnclosure: CoordinateEnclosure2D
}

/// Certifies discrete intersections of two bounded rational B-spline curves
/// directly in their two-dimensional parameter chart.
package struct RationalBSplineCurveIntersector2D {
    package init() {}

    /// The acceptance closure owns the consumer-specific precision policy.
    /// CADGeometry proves existence and uniqueness; a surface-lift consumer,
    /// for example, can require the lifted spatial enclosure to fit its
    /// distance budget without turning distance into an arbitrary UV value.
    package func intersections(first: BSplineCurve2D, second: BSplineCurve2D,
        maximumSubdivisionDepth: Int, maximumSubdivisionCells: Int,
        accepting: (RationalBSplineCurveIntersection2D, inout OriginalQueryExecution) throws -> Bool,
        tolerance: ModelingTolerance) throws -> [RationalBSplineCurveIntersection2D] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try intersections(first: first, second: second,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumSubdivisionCells: maximumSubdivisionCells,
            accepting: accepting, tolerance: tolerance, using: &execution)
    }

    package func intersections(
        first: BSplineCurve2D,
        second: BSplineCurve2D,
        maximumSubdivisionDepth: Int,
        maximumSubdivisionCells: Int,
        accepting: (RationalBSplineCurveIntersection2D, inout OriginalQueryExecution) throws -> Bool,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [RationalBSplineCurveIntersection2D] {
        try execution.consumeWork(1)
        try tolerance.validate()
        try first.validate(tolerance: tolerance, using: &execution)
        try second.validate(tolerance: tolerance, using: &execution)
        guard maximumSubdivisionDepth >= 0,
              maximumSubdivisionDepth <= 48,
              maximumSubdivisionCells > 0 else {
            throw failure(
                .resourceLimitExceeded,
                tolerance: tolerance,
                "Rational pcurve intersection limits are outside the supported resource envelope."
            )
        }

        let firstPatches = try first.rationalBezierPatches(tolerance: tolerance, using: &execution)
        let secondPatches = try second.rationalBezierPatches(tolerance: tolerance, using: &execution)
        var pending: [Cell] = []
        var result: [RationalBSplineCurveIntersection2D] = []
        let pairCount = try exactScalarCount(firstPatches.count, secondPatches.count, multiply: true)
        try OriginalCoefficientAllocation.reserve(count: pairCount, of: Cell.self, using: &execution)
        pending.reserveCapacity(pairCount)
        var pendingCapacity = pairCount
        var resultCapacity = 0
        for firstPatch in firstPatches.reversed() {
            try execution.consumeWork(1)
            for secondPatch in secondPatches.reversed() {
                try execution.consumeWork(1)
                if let tangencies = try certifiedQuadraticLineTangencies(
                    first: firstPatch,
                    second: secondPatch,
                    tolerance: tolerance
                , using: &execution) {
                    for tangency in tangencies {
                        try execution.consumeWork(1)
                        let accepted = try accepting(tangency, &execution)
                        try execution.checkpoint()
                        guard accepted else {
                            throw failure(
                                .resourceLimitExceeded,
                                residual: tangency.pointEnclosure.maximumWidth,
                                tolerance: tolerance,
                                "A certified quadratic-line tangency did not satisfy the consumer precision contract."
                            )
                        }
                        try appendUnique(tangency, to: &result, capacity: &resultCapacity, using: &execution)
                    }
                    continue
                }
                let patch = try DifferencePatch(
                    first: firstPatch,
                    second: secondPatch,
                    tolerance: tolerance, using: &execution
                )
                try OriginalCoefficientAllocation.reserveAppend(to: &pending, capacity: &pendingCapacity, using: &execution)
                pending.append(Cell(
                    patch: try patch.expandedForBoundaryCertification(using: &execution),
                    depth: 0
                ))
            }
        }

        var remainingCells = maximumSubdivisionCells
        var acceptedRootDomains: [DifferencePatch] = []
        var unresolvedLeaves: [DifferencePatch] = []
        var acceptedCapacity = 0, unresolvedCapacity = 0
        while let cell = pending.popLast() {
            if try acceptedRootDomains.contains(where: {
                try execution.consumeWork(1)
                return $0.containsParameterDomain(of: cell.patch)
            }) {
                continue
            }
            guard remainingCells > 0 else {
                throw failure(
                    .resourceLimitExceeded,
                    residual: Double(result.count),
                    tolerance: tolerance,
                    "Rational pcurve intersection exceeded its certified cell budget."
                )
            }
            remainingCells -= 1
            try execution.visitGeometricCell(depth: cell.depth)
            switch try cell.patch.rootCertificate(using: &execution) {
            case .excluded:
                continue
            case let .unique(firstNormalized, secondNormalized):
                guard let candidate = try cell.patch.intersectionEnclosure(
                    firstNormalized: firstNormalized,
                    secondNormalized: secondNormalized,
                    tolerance: tolerance
                , using: &execution) else { continue }
                let accepted = try accepting(candidate, &execution)
                try execution.checkpoint()
                if accepted {
                    try appendUnique(candidate, to: &result, capacity: &resultCapacity, using: &execution)
                    try OriginalCoefficientAllocation.reserveAppend(to: &acceptedRootDomains, capacity: &acceptedCapacity, using: &execution)
                    acceptedRootDomains.append(cell.patch)
                    continue
                }
                guard cell.depth < maximumSubdivisionDepth else {
                    if cell.patch.intersectsOriginalParameterDomain {
                        try OriginalCoefficientAllocation.reserveAppend(to: &unresolvedLeaves, capacity: &unresolvedCapacity, using: &execution)
                        unresolvedLeaves.append(cell.patch)
                    }
                    continue
                }
                try OriginalCoefficientAllocation.reserveAppend(to: &pending, capacity: &pendingCapacity, using: &execution)
                pending.append(Cell(
                    patch: try cell.patch.refinedAroundUniqueRoot(
                        firstNormalized: firstNormalized,
                        secondNormalized: secondNormalized
                    , using: &execution),
                    depth: cell.depth + 1
                ))
                continue
            case .unresolved:
                break
            }

            guard cell.depth < maximumSubdivisionDepth else {
                if cell.patch.intersectsOriginalParameterDomain {
                    try OriginalCoefficientAllocation.reserveAppend(to: &unresolvedLeaves, capacity: &unresolvedCapacity, using: &execution)
                        unresolvedLeaves.append(cell.patch)
                }
                continue
            }
            for child in try cell.patch.subdivided(using: &execution).reversed() {
                try execution.consumeWork(1)
                try OriginalCoefficientAllocation.reserveAppend(to: &pending, capacity: &pendingCapacity, using: &execution)
                pending.append(Cell(patch: child, depth: cell.depth + 1))
            }
        }
        if let unresolved = try unresolvedLeaves.first(where: { leaf in
            try execution.consumeWork(1)
            return try acceptedRootDomains.contains(where: {
                try execution.consumeWork(1)
                return $0.containsParameterDomain(of: leaf)
            }) == false
        }) {
            throw failure(
                .resourceLimitExceeded,
                residual: unresolved.maximumParameterWidth,
                tolerance: tolerance,
                "Rational pcurve intersection left an unresolved proof or precision cell at the subdivision limit "
                    + "(first [\(unresolved.firstLower), \(unresolved.firstUpper)], "
                    + "second [\(unresolved.secondLower), \(unresolved.secondUpper)])."
            )
        }
        let ordered = try orderedRoots(result, using: &execution)
        try execution.checkpoint()
        return ordered
    }

    private func rootOrder(_ first: RationalBSplineCurveIntersection2D, _ second: RationalBSplineCurveIntersection2D) -> Bool {
        if first.firstParameterEnclosure.midpoint != second.firstParameterEnclosure.midpoint {
            return first.firstParameterEnclosure.midpoint < second.firstParameterEnclosure.midpoint
        }
        return first.secondParameterEnclosure.midpoint < second.secondParameterEnclosure.midpoint
    }

    private func orderedRoots(_ roots: [RationalBSplineCurveIntersection2D],
        using execution: inout OriginalQueryExecution) throws -> [RationalBSplineCurveIntersection2D] {
        var ordered = try OriginalCoefficientAllocation.map(elements: roots, using: &execution) { value, _ in value }
        guard ordered.count > 1 else { return ordered }
        var scratch = try OriginalCoefficientAllocation.map(elements: roots, using: &execution) { value, _ in value }
        var width = 1
        while width < ordered.count {
            var start = 0
            while start < ordered.count {
                let middle = start + min(width, ordered.count - start)
                let end = middle + min(width, ordered.count - middle)
                var left = start, right = middle, output = start
                while left < middle || right < end {
                    try execution.consumeWork(1)
                    let takeRight: Bool
                    if left == middle { takeRight = true }
                    else if right == end { takeRight = false }
                    else { try execution.consumeWork(1); takeRight = rootOrder(ordered[right], ordered[left]) }
                    if takeRight { scratch[output] = ordered[right]; right += 1 }
                    else { scratch[output] = ordered[left]; left += 1 }
                    output += 1
                }
                start = end
            }
            swap(&ordered, &scratch)
            if width > ordered.count / 2 { break }
            width *= 2
        }
        return ordered
    }

    private func appendUnique(
        _ intersection: RationalBSplineCurveIntersection2D,
        to result: inout [RationalBSplineCurveIntersection2D], capacity: inout Int
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard let index = try result.firstIndex(where: {
            try execution.consumeWork(1)
            return $0.firstParameterEnclosure.intersects(
                intersection.firstParameterEnclosure
            ) && $0.secondParameterEnclosure.intersects(
                intersection.secondParameterEnclosure
            )
        }) else {
            try OriginalCoefficientAllocation.reserveAppend(to: &result, capacity: &capacity, using: &execution)
            result.append(intersection)
            return
        }
        let existingWidth = result[index].firstParameterEnclosure.width
            + result[index].secondParameterEnclosure.width
        let candidateWidth = intersection.firstParameterEnclosure.width
            + intersection.secondParameterEnclosure.width
        if candidateWidth < existingWidth {
            result[index] = intersection
        }
    }

    private func certifiedQuadraticLineTangencies(
        first: RationalBezierCurvePatch2D,
        second: RationalBezierCurvePatch2D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [RationalBSplineCurveIntersection2D]? {
        try execution.consumeWork(1)
        if first.degree == 2, second.degree == 1 {
            return try certifiedQuadraticLineTangencies(
                quadratic: first,
                line: second,
                quadraticIsFirst: true,
                tolerance: tolerance
            , using: &execution)
        }
        if first.degree == 1, second.degree == 2 {
            return try certifiedQuadraticLineTangencies(
                quadratic: second,
                line: first,
                quadraticIsFirst: false,
                tolerance: tolerance
            , using: &execution)
        }
        return nil
    }

    private func certifiedQuadraticLineTangencies(
        quadratic: RationalBezierCurvePatch2D,
        line: RationalBezierCurvePatch2D,
        quadraticIsFirst: Bool,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [RationalBSplineCurveIntersection2D]? {
        try execution.consumeWork(1)
        guard quadratic.controlPoints.count == 3,
              quadratic.weights.count == 3,
              line.controlPoints.count == 2,
              line.weights.count == 2 else {
            return nil
        }
        let start = line.controlPoints[0]
        let end = line.controlPoints[1]
        let lineA = try ExactExpansionArithmetic.subtract(try OriginalCoefficientAllocation.singleton(start.y, using: &execution), try OriginalCoefficientAllocation.singleton(end.y, using: &execution), using: &execution)
        let lineB = try ExactExpansionArithmetic.subtract(try OriginalCoefficientAllocation.singleton(end.x, using: &execution), try OriginalCoefficientAllocation.singleton(start.x, using: &execution), using: &execution)
        let lineC = try ExactExpansionArithmetic.subtract(
            try ExactExpansionArithmetic.multiply(try OriginalCoefficientAllocation.singleton(start.x, using: &execution), try OriginalCoefficientAllocation.singleton(end.y, using: &execution), using: &execution),
            try ExactExpansionArithmetic.multiply(try OriginalCoefficientAllocation.singleton(end.x, using: &execution), try OriginalCoefficientAllocation.singleton(start.y, using: &execution), using: &execution)
        , using: &execution)
        let bernstein = try OriginalCoefficientAllocation.map(elements: quadratic.controlPoints.indices, using: &execution) { index, execution in
            let weight = quadratic.weights[index]
            let point = quadratic.controlPoints[index]
            let homogeneousX = try ExactExpansionArithmetic.multiply(
                try OriginalCoefficientAllocation.singleton(point.x, using: &execution),
                try OriginalCoefficientAllocation.singleton(weight, using: &execution)
            , using: &execution)
            let homogeneousY = try ExactExpansionArithmetic.multiply(
                try OriginalCoefficientAllocation.singleton(point.y, using: &execution),
                try OriginalCoefficientAllocation.singleton(weight, using: &execution)
            , using: &execution)
            return try ExactExpansionArithmetic.add(
                try ExactExpansionArithmetic.add(
                    try ExactExpansionArithmetic.multiply(lineA, homogeneousX, using: &execution),
                    try ExactExpansionArithmetic.multiply(lineB, homogeneousY, using: &execution)
                , using: &execution),
                try ExactExpansionArithmetic.multiply(lineC, try OriginalCoefficientAllocation.singleton(weight, using: &execution), using: &execution)
            , using: &execution)
        }
        let constant = bernstein[0]
        let linear = try ExactExpansionArithmetic.multiply(
            try ExactExpansionArithmetic.subtract(bernstein[1], bernstein[0], using: &execution),
            try OriginalCoefficientAllocation.singleton(2.0, using: &execution)
        , using: &execution)
        let quadraticCoefficient = try ExactExpansionArithmetic.add(
            try ExactExpansionArithmetic.subtract(
                bernstein[0],
                try ExactExpansionArithmetic.multiply(bernstein[1], try OriginalCoefficientAllocation.singleton(2.0, using: &execution), using: &execution)
            , using: &execution),
            bernstein[2]
        , using: &execution)
        guard try ExactExpansionArithmetic.sign(quadraticCoefficient, using: &execution) != .zero else {
            return nil
        }
        let discriminant = try ExactExpansionArithmetic.subtract(
            try ExactExpansionArithmetic.multiply(linear, linear, using: &execution),
            try ExactExpansionArithmetic.multiply(
                try OriginalCoefficientAllocation.singleton(4.0, using: &execution),
                try ExactExpansionArithmetic.multiply(
                    quadraticCoefficient,
                    constant
                , using: &execution)
            , using: &execution)
        , using: &execution)
        guard try ExactExpansionArithmetic.sign(discriminant, using: &execution) == .zero else {
            return nil
        }
        let numerator = try -expansionEnclosure(linear, using: &execution)
        let denominator = try expansionEnclosure(
            try ExactExpansionArithmetic.multiply(quadraticCoefficient, try OriginalCoefficientAllocation.singleton(2.0, using: &execution), using: &execution)
        , using: &execution)
        guard let root = numerator.divided(by: denominator),
              let boundedRoot = root.intersection(with: OutwardScalarInterval(
                  lower: 0.0,
                  upper: 1.0
              )) else {
            return []
        }
        let quadraticPosition = try rationalPositionEnclosure(
            quadratic,
            parameter: boundedRoot,
            tolerance: tolerance
        , using: &execution)
        let lineParameter = try lineParameterEnclosure(
            for: quadraticPosition,
            line: line,
            tolerance: tolerance
        , using: &execution)
        guard let boundedLineParameter = lineParameter.intersection(
            with: OutwardScalarInterval(lower: 0.0, upper: 1.0)
        ) else {
            return []
        }
        let linePosition = try rationalPositionEnclosure(
            line,
            parameter: boundedLineParameter,
            tolerance: tolerance
        , using: &execution)
        guard let x = quadraticPosition.x.intersection(with: linePosition.x),
              let y = quadraticPosition.y.intersection(with: linePosition.y) else {
            return []
        }
        let quadraticParameter = affineImage(
            boundedRoot,
            lower: quadratic.lower,
            upper: quadratic.upper
        )
        let linearParameter = affineImage(
            boundedLineParameter,
            lower: line.lower,
            upper: line.upper
        )
        let firstParameter = quadraticIsFirst
            ? quadraticParameter
            : linearParameter
        let secondParameter = quadraticIsFirst
            ? linearParameter
            : quadraticParameter
        return try OriginalCoefficientAllocation.singleton(RationalBSplineCurveIntersection2D(
            firstParameterEnclosure: try scalarInterval(
                firstParameter,
                tolerance: tolerance
            ),
            secondParameterEnclosure: try scalarInterval(
                secondParameter,
                tolerance: tolerance
            ),
            pointEnclosure: CoordinateEnclosure2D(
                x: try scalarInterval(x, tolerance: tolerance),
                y: try scalarInterval(y, tolerance: tolerance)
            )
        ), using: &execution)
    }

    private func expansionEnclosure(
        _ expansion: ExactExpansionArithmetic.Scalar
    , using execution: inout OriginalQueryExecution) throws -> OutwardScalarInterval {
        try execution.consumeWork(1)
        var result = OutwardScalarInterval.exact(0)
        for value in expansion { try execution.consumeWork(1); result = result + .exact(value) }
        return result
    }

    private func rationalPositionEnclosure(
        _ patch: RationalBezierCurvePatch2D,
        parameter: OutwardScalarInterval,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> (x: OutwardScalarInterval, y: OutwardScalarInterval) {
        try execution.consumeWork(1)
        var x = try OriginalCoefficientAllocation.map(elements: patch.controlPoints.indices, using: &execution) { index, _ in
            OutwardScalarInterval.exact(patch.controlPoints[index].x) * .exact(patch.weights[index])
        }
        var y = try OriginalCoefficientAllocation.map(elements: patch.controlPoints.indices, using: &execution) { index, _ in
            OutwardScalarInterval.exact(patch.controlPoints[index].y) * .exact(patch.weights[index])
        }
        var weights = try OriginalCoefficientAllocation.map(elements: patch.weights, using: &execution) { value, _ in OutwardScalarInterval.exact(value) }
        let complement = OutwardScalarInterval.exact(1) - parameter
        while x.count > 1 {
            try execution.consumeWork(1)
            x = try OriginalCoefficientAllocation.map(first: x, second: x.dropFirst(), using: &execution) { pair, _ in
                pair.0 * complement + pair.1 * parameter
            }
            y = try OriginalCoefficientAllocation.map(first: y, second: y.dropFirst(), using: &execution) { pair, _ in
                pair.0 * complement + pair.1 * parameter
            }
            weights = try OriginalCoefficientAllocation.map(first: weights, second: weights.dropFirst(), using: &execution) { pair, _ in
                pair.0 * complement + pair.1 * parameter
            }
        }
        guard let xValue = x[0].divided(by: weights[0]),
              let yValue = y[0].divided(by: weights[0]) else {
            throw failure(
                .singularSystem,
                tolerance: tolerance,
                "Rational tangency enclosure crossed a non-positive denominator."
            )
        }
        return (xValue, yValue)
    }

    private func lineParameterEnclosure(
        for point: (x: OutwardScalarInterval, y: OutwardScalarInterval),
        line: RationalBezierCurvePatch2D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> OutwardScalarInterval {
        try execution.consumeWork(1)
        let start = line.controlPoints[0]
        let end = line.controlPoints[1]
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let coordinate: OutwardScalarInterval
        let startCoordinate: Double
        let delta: Double
        if abs(deltaX) >= abs(deltaY) {
            coordinate = point.x
            startCoordinate = start.x
            delta = deltaX
        } else {
            coordinate = point.y
            startCoordinate = start.y
            delta = deltaY
        }
        guard delta.isFinite, delta != 0.0,
              let chordFraction = (
                  coordinate - .exact(startCoordinate)
              ).divided(by: .exact(delta)) else {
            throw failure(
                .singularSystem,
                tolerance: tolerance,
                "Rational line tangency has no stable parameter coordinate."
            )
        }
        let firstWeight = OutwardScalarInterval.exact(line.weights[0])
        let secondWeight = OutwardScalarInterval.exact(line.weights[1])
        let numerator = chordFraction * firstWeight
        let denominator = (
            OutwardScalarInterval.exact(1.0) - chordFraction
        ) * secondWeight + chordFraction * firstWeight
        guard let parameter = numerator.divided(by: denominator) else {
            throw failure(
                .singularSystem,
                tolerance: tolerance,
                "Rational line tangency parameter crossed a zero denominator."
            )
        }
        return parameter
    }

    private func affineImage(
        _ normalized: OutwardScalarInterval,
        lower: Double,
        upper: Double
    ) -> OutwardScalarInterval {
        .exact(lower) + .exact(upper - lower) * normalized
    }

    private func scalarInterval(
        _ interval: OutwardScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard interval.isFinite else {
            throw failure(
                .resourceLimitExceeded,
                tolerance: tolerance,
                "Certified rational tangency exceeded finite interval representation."
            )
        }
        return try ScalarInterval(lower: interval.lower, upper: interval.upper)
    }

    private func failure(
        _ code: KernelErrorCode,
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: code,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }

    private struct Cell {
        let patch: DifferencePatch
        let depth: Int
    }
}

private struct DifferencePatch {
    enum RootCertificate {
        case excluded
        case unique(
            firstNormalized: OutwardScalarInterval,
            secondNormalized: OutwardScalarInterval
        )
        case unresolved
    }

    private struct Vector {
        let x: OutwardScalarInterval
        let y: OutwardScalarInterval

        func midpoint(with other: Vector) -> Vector {
            interpolated(
                to: other,
                parameter: OutwardScalarInterval.exact(0.5)
            )
        }

        func interpolated(
            to other: Vector,
            parameter: OutwardScalarInterval
        ) -> Vector {
            let complement = OutwardScalarInterval.exact(1.0) - parameter
            return Vector(
                x: x * complement + other.x * parameter,
                y: y * complement + other.y * parameter
            )
        }

        var isFinite: Bool {
            x.isFinite && y.isFinite
        }
    }

    private struct HomogeneousPoint {
        let x: OutwardScalarInterval
        let y: OutwardScalarInterval
        let weight: OutwardScalarInterval

        init(point: Point2D, weight: Double) {
            let exactWeight = OutwardScalarInterval.exact(weight)
            x = OutwardScalarInterval.exact(point.x) * exactWeight
            y = OutwardScalarInterval.exact(point.y) * exactWeight
            self.weight = exactWeight
        }

        func interpolated(
            to other: HomogeneousPoint,
            parameter: OutwardScalarInterval
        ) -> HomogeneousPoint {
            let complement = OutwardScalarInterval.exact(1.0) - parameter
            return HomogeneousPoint(
                x: x * complement + other.x * parameter,
                y: y * complement + other.y * parameter,
                weight: weight * complement + other.weight * parameter
            )
        }

        private init(
            x: OutwardScalarInterval,
            y: OutwardScalarInterval,
            weight: OutwardScalarInterval
        ) {
            self.x = x
            self.y = y
            self.weight = weight
        }

        var isFiniteAndPositive: Bool {
            x.isFinite && y.isFinite && weight.isFinite && weight.lower > 0.0
        }
    }

    private let controlNet: [[Vector]]
    private let sourceFirstControls: [HomogeneousPoint]
    private let sourceSecondControls: [HomogeneousPoint]
    private let sourceControlNet: [[Vector]]
    private let sourceFirstLower: Double
    private let sourceFirstUpper: Double
    private let sourceSecondLower: Double
    private let sourceSecondUpper: Double
    private let firstSourceDomainLower: Double
    private let firstSourceDomainUpper: Double
    private let secondSourceDomainLower: Double
    private let secondSourceDomainUpper: Double
    let firstLower: Double
    let firstUpper: Double
    let secondLower: Double
    let secondUpper: Double

    init(
        first: RationalBezierCurvePatch2D,
        second: RationalBezierCurvePatch2D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        guard first.controlPoints.count == first.weights.count,
              second.controlPoints.count == second.weights.count,
              first.controlPoints.count >= 2,
              second.controlPoints.count >= 2 else {
            throw Self.failure(
                .invalidInput,
                tolerance: tolerance,
                "Rational pcurve difference requires non-empty matching control data."
            )
        }
        let firstControls = try OriginalCoefficientAllocation.map(elements: first.controlPoints.indices, using: &execution) { index, _ in
            HomogeneousPoint(
                point: first.controlPoints[index],
                weight: first.weights[index]
            )
        }
        let secondControls = try OriginalCoefficientAllocation.map(elements: second.controlPoints.indices, using: &execution) { index, _ in
            HomogeneousPoint(
                point: second.controlPoints[index],
                weight: second.weights[index]
            )
        }
        guard try firstControls.allSatisfy({ try execution.consumeWork(1); return $0.isFiniteAndPositive }),
              try secondControls.allSatisfy({ try execution.consumeWork(1); return $0.isFiniteAndPositive }) else {
            throw Self.failure(
                .resourceLimitExceeded,
                tolerance: tolerance,
                "Rational pcurve homogeneous controls exceeded finite positive interval arithmetic."
            )
        }
        let controlNet = try Self.differenceControlNet(
            first: firstControls,
            second: secondControls
        , using: &execution)
        self.init(
            controlNet: controlNet,
            sourceFirstControls: firstControls,
            sourceSecondControls: secondControls,
            sourceControlNet: controlNet,
            sourceFirstLower: first.lower,
            sourceFirstUpper: first.upper,
            sourceSecondLower: second.lower,
            sourceSecondUpper: second.upper,
            firstSourceDomainLower: 0.0,
            firstSourceDomainUpper: 1.0,
            secondSourceDomainLower: 0.0,
            secondSourceDomainUpper: 1.0,
            firstLower: first.lower,
            firstUpper: first.upper,
            secondLower: second.lower,
            secondUpper: second.upper
        )
        guard try controlNet.allSatisfy({ row in try row.allSatisfy { try execution.consumeWork(1); return $0.isFinite } }) else {
            throw Self.failure(
                .resourceLimitExceeded,
                tolerance: tolerance,
                "Rational pcurve difference exceeded finite interval arithmetic."
            )
        }
    }

    private init(
        controlNet: [[Vector]],
        sourceFirstControls: [HomogeneousPoint],
        sourceSecondControls: [HomogeneousPoint],
        sourceControlNet: [[Vector]],
        sourceFirstLower: Double,
        sourceFirstUpper: Double,
        sourceSecondLower: Double,
        sourceSecondUpper: Double,
        firstSourceDomainLower: Double,
        firstSourceDomainUpper: Double,
        secondSourceDomainLower: Double,
        secondSourceDomainUpper: Double,
        firstLower: Double,
        firstUpper: Double,
        secondLower: Double,
        secondUpper: Double
    ) {
        self.controlNet = controlNet
        self.sourceFirstControls = sourceFirstControls
        self.sourceSecondControls = sourceSecondControls
        self.sourceControlNet = sourceControlNet
        self.sourceFirstLower = sourceFirstLower
        self.sourceFirstUpper = sourceFirstUpper
        self.sourceSecondLower = sourceSecondLower
        self.sourceSecondUpper = sourceSecondUpper
        self.firstSourceDomainLower = firstSourceDomainLower
        self.firstSourceDomainUpper = firstSourceDomainUpper
        self.secondSourceDomainLower = secondSourceDomainLower
        self.secondSourceDomainUpper = secondSourceDomainUpper
        self.firstLower = firstLower
        self.firstUpper = firstUpper
        self.secondLower = secondLower
        self.secondUpper = secondUpper
    }

    var maximumParameterWidth: Double {
        max(firstUpper - firstLower, secondUpper - secondLower)
    }

    /// Boundary certification deliberately evaluates a small extension of
    /// each source curve so a root at an authored endpoint is interior to the
    /// proof cell. A proof-only cell entirely outside either authored domain
    /// cannot contribute a modeled intersection or an unresolved modeled
    /// root.
    var intersectsOriginalParameterDomain: Bool {
        firstSourceDomainUpper >= 0.0
            && firstSourceDomainLower <= 1.0
            && secondSourceDomainUpper >= 0.0
            && secondSourceDomainLower <= 1.0
    }

    func rootCertificate(using execution: inout OriginalQueryExecution) throws -> RootCertificate {
        try execution.consumeWork(1)
        guard try excludesZero(using: &execution) == false else { return .excluded }
        let value = try centerValue(using: &execution)
        let firstDerivative = try derivativeBounds(alongFirst: true, using: &execution)
        let secondDerivative = try derivativeBounds(alongFirst: false, using: &execution)
        let a = firstDerivative.x.midpoint
        let b = secondDerivative.x.midpoint
        let c = firstDerivative.y.midpoint
        let d = secondDerivative.y.midpoint
        let determinant = a * d - b * c
        guard determinant.isFinite, determinant != 0.0 else {
            return .unresolved
        }
        try OriginalCoefficientAllocation.reserve(count: 2, of: [Double].self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 2, of: Double.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 2, of: Double.self, using: &execution)
        let inverse = [
            [d / determinant, -b / determinant],
            [-c / determinant, a / determinant],
        ]
        guard try inverse.allSatisfy({ row in try row.allSatisfy { try execution.consumeWork(1); return $0.isFinite } }) else {
            return .unresolved
        }
        try OriginalCoefficientAllocation.reserve(count: 2, of: [OutwardScalarInterval].self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 2, of: OutwardScalarInterval.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 2, of: OutwardScalarInterval.self, using: &execution)
        let jacobian = [
            [firstDerivative.x, secondDerivative.x],
            [firstDerivative.y, secondDerivative.y],
        ]
        try OriginalCoefficientAllocation.reserve(count: 2, of: OutwardScalarInterval.self, using: &execution)
        let functionValue = [value.x, value.y]
        let unit = OutwardScalarInterval(lower: 0.0, upper: 1.0)
        let radius = OutwardScalarInterval(lower: -0.5, upper: 0.5)
        try OriginalCoefficientAllocation.reserve(count: 2, of: OutwardScalarInterval.self, using: &execution)
        var image: [OutwardScalarInterval] = []; image.reserveCapacity(2)
        for row in 0..<2 {
                try execution.consumeWork(1)
            var component = OutwardScalarInterval.exact(0.5)
            for inner in 0..<2 {
                try execution.consumeWork(1)
                component = component
                    - OutwardScalarInterval(inverse[row][inner])
                        * functionValue[inner]
            }
            for column in 0..<2 {
                try execution.consumeWork(1)
                var preconditioned = OutwardScalarInterval.exact(0.0)
                for inner in 0..<2 {
                try execution.consumeWork(1)
                    preconditioned = preconditioned
                        + OutwardScalarInterval(inverse[row][inner])
                            * jacobian[inner][column]
                }
                component = component
                    + (
                        OutwardScalarInterval.exact(
                            row == column ? 1.0 : 0.0
                        ) - preconditioned
                    ) * radius
            }
            image.append(component)
        }
        if try image.contains(where: { try execution.consumeWork(1); return $0.intersection(with: unit) == nil }) {
            return .excluded
        }
        if try image.allSatisfy({ try execution.consumeWork(1); return $0.isStrictlyInside(unit) }) {
            return .unique(
                firstNormalized: image[0],
                secondNormalized: image[1]
            )
        }
        return .unresolved
    }

    func intersectionEnclosure(
        firstNormalized: OutwardScalarInterval,
        secondNormalized: OutwardScalarInterval,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> RationalBSplineCurveIntersection2D? {
        try execution.consumeWork(1)
        let firstSourceParameters = affineImage(
            firstNormalized,
            lower: firstSourceDomainLower,
            upper: firstSourceDomainUpper
        )
        let secondSourceParameters = affineImage(
            secondNormalized,
            lower: secondSourceDomainLower,
            upper: secondSourceDomainUpper
        )
        let sourceUnit = OutwardScalarInterval(lower: 0.0, upper: 1.0)
        guard let boundedFirstSourceParameters = firstSourceParameters
            .intersection(with: sourceUnit),
              let boundedSecondSourceParameters = secondSourceParameters
            .intersection(with: sourceUnit) else {
            return nil
        }
        let firstParameters = affineImage(
            boundedFirstSourceParameters,
            lower: sourceFirstLower,
            upper: sourceFirstUpper
        )
        let secondParameters = affineImage(
            boundedSecondSourceParameters,
            lower: sourceSecondLower,
            upper: sourceSecondUpper
        )
        let firstPosition = try positionEnclosure(
            controls: sourceFirstControls,
            normalizedParameter: boundedFirstSourceParameters,
            tolerance: tolerance
        , using: &execution)
        let secondPosition = try positionEnclosure(
            controls: sourceSecondControls,
            normalizedParameter: boundedSecondSourceParameters,
            tolerance: tolerance
        , using: &execution)
        guard let x = firstPosition.x.intersection(with: secondPosition.x),
              let y = firstPosition.y.intersection(with: secondPosition.y) else {
            return nil
        }
        return RationalBSplineCurveIntersection2D(
            firstParameterEnclosure: try scalarInterval(
                firstParameters,
                tolerance: tolerance
            ),
            secondParameterEnclosure: try scalarInterval(
                secondParameters,
                tolerance: tolerance
            ),
            pointEnclosure: CoordinateEnclosure2D(
                x: try scalarInterval(x, tolerance: tolerance),
                y: try scalarInterval(y, tolerance: tolerance)
            )
        )
    }

    func subdivided(using execution: inout OriginalQueryExecution) throws -> [DifferencePatch] {
        try execution.consumeWork(1)
        // This is a proof-domain overlap, not a modeling tolerance. Both
        // children contain the shared split in their strict interior so a
        // root on an artificial subdivision boundary remains certifiable.
        try OriginalCoefficientAllocation.reserve(count: 2, of: DifferencePatch.self, using: &execution)
        let overlap = 1.0 / 64.0
        if firstUpper - firstLower >= secondUpper - secondLower {
            return [
                try restrictedFirst(from: 0.0, to: 0.5 + overlap, using: &execution),
                try restrictedFirst(from: 0.5 - overlap, to: 1.0, using: &execution),
            ]
        }
        return [
            try restrictedSecond(from: 0.0, to: 0.5 + overlap, using: &execution),
            try restrictedSecond(from: 0.5 - overlap, to: 1.0, using: &execution),
        ]
    }

    func expandedForBoundaryCertification(using execution: inout OriginalQueryExecution) throws -> DifferencePatch {
        try execution.consumeWork(1)
        let extensionFraction = 1.0 / 64.0
        let lower = -extensionFraction
        let upper = 1.0 + extensionFraction
        let firstControls = try restricted(
            sourceFirstControls,
            from: lower,
            to: upper
        , using: &execution) { first, second, parameter, _ in
            first.interpolated(to: second, parameter: parameter)
        }
        let secondControls = try restricted(
            sourceSecondControls,
            from: lower,
            to: upper
        , using: &execution) { first, second, parameter, _ in
            first.interpolated(to: second, parameter: parameter)
        }
        guard try firstControls.allSatisfy({ try execution.consumeWork(1); return $0.isFiniteAndPositive }),
              try secondControls.allSatisfy({ try execution.consumeWork(1); return $0.isFiniteAndPositive }) else {
            return self
        }
        return try restrictedDomain(
            firstLower: lower,
            firstUpper: upper,
            secondLower: lower,
            secondUpper: upper
        , using: &execution)
    }

    func containsParameterDomain(of other: DifferencePatch) -> Bool {
        firstLower <= other.firstLower
            && other.firstUpper <= firstUpper
            && secondLower <= other.secondLower
            && other.secondUpper <= secondUpper
    }

    func refinedAroundUniqueRoot(
        firstNormalized: OutwardScalarInterval,
        secondNormalized: OutwardScalarInterval
    , using execution: inout OriginalQueryExecution) throws -> DifferencePatch {
        try execution.consumeWork(1)
        let firstRange = paddedRootRange(firstNormalized)
        let secondRange = paddedRootRange(secondNormalized)
        return try restrictedFirst(from: firstRange.lower, to: firstRange.upper, using: &execution)
            .restrictedSecond(
                from: secondRange.lower,
                to: secondRange.upper
            , using: &execution)
    }

    private func paddedRootRange(
        _ root: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        // A unique root is strictly inside the unit proof domain. Do not let
        // padding restore that entire domain: precision refinement must contract.
        let padding = min(max(root.width, Double.ulpOfOne),
            min(root.lower, 1.0 - root.upper) * 0.5)
        return OutwardScalarInterval(
            lower: max(0.0, (root.lower - padding).nextDown),
            upper: min(1.0, (root.upper + padding).nextUp)
        )
    }

    private func restrictedFirst(
        from lowerFraction: Double,
        to upperFraction: Double
    , using execution: inout OriginalQueryExecution) throws -> DifferencePatch {
        try execution.consumeWork(1)
        let span = firstSourceDomainUpper - firstSourceDomainLower
        return try restrictedDomain(
            firstLower: firstSourceDomainLower + span * lowerFraction,
            firstUpper: firstSourceDomainLower + span * upperFraction,
            secondLower: secondSourceDomainLower,
            secondUpper: secondSourceDomainUpper
        , using: &execution)
    }

    private func restrictedSecond(
        from lowerFraction: Double,
        to upperFraction: Double
    , using execution: inout OriginalQueryExecution) throws -> DifferencePatch {
        try execution.consumeWork(1)
        let span = secondSourceDomainUpper - secondSourceDomainLower
        return try restrictedDomain(
            firstLower: firstSourceDomainLower,
            firstUpper: firstSourceDomainUpper,
            secondLower: secondSourceDomainLower + span * lowerFraction,
            secondUpper: secondSourceDomainLower + span * upperFraction
        , using: &execution)
    }

    private func restrictedDomain(
        firstLower: Double,
        firstUpper: Double,
        secondLower: Double,
        secondUpper: Double
    , using execution: inout OriginalQueryExecution) throws -> DifferencePatch {
        try execution.consumeWork(1)
        let firstRestrictedNet = try restrictedFirst(
            sourceControlNet,
            from: firstLower,
            to: firstUpper
        , using: &execution)
        let currentControlNet = try restrictedSecond(
            firstRestrictedNet,
            from: secondLower,
            to: secondUpper
        , using: &execution)
        return DifferencePatch(
            controlNet: currentControlNet,
            sourceFirstControls: sourceFirstControls,
            sourceSecondControls: sourceSecondControls,
            sourceControlNet: sourceControlNet,
            sourceFirstLower: sourceFirstLower,
            sourceFirstUpper: sourceFirstUpper,
            sourceSecondLower: sourceSecondLower,
            sourceSecondUpper: sourceSecondUpper,
            firstSourceDomainLower: firstLower,
            firstSourceDomainUpper: firstUpper,
            secondSourceDomainLower: secondLower,
            secondSourceDomainUpper: secondUpper,
            firstLower: sourceFirstLower
                + (sourceFirstUpper - sourceFirstLower) * firstLower,
            firstUpper: sourceFirstLower
                + (sourceFirstUpper - sourceFirstLower) * firstUpper,
            secondLower: sourceSecondLower
                + (sourceSecondUpper - sourceSecondLower) * secondLower,
            secondUpper: sourceSecondLower
                + (sourceSecondUpper - sourceSecondLower) * secondUpper
        )
    }

    private static func differenceControlNet(first: [HomogeneousPoint], second: [HomogeneousPoint],
        using execution: inout OriginalQueryExecution) throws -> [[Vector]] {
        try OriginalCoefficientAllocation.map(elements: first, using: &execution) { firstControl, execution in
            try OriginalCoefficientAllocation.map(elements: second, using: &execution) { secondControl, _ in
                Vector(x: firstControl.x * secondControl.weight - secondControl.x * firstControl.weight,
                    y: firstControl.y * secondControl.weight - secondControl.y * firstControl.weight)
            }
        }
    }

    private func excludesZero(using execution: inout OriginalQueryExecution) throws -> Bool {
        // Keep each original short-circuit axis scan without materializing a flattened net.
        for axis in 0..<4 {
            var excluded = true
            scan: for row in controlNet { for value in row {
                try execution.consumeWork(1)
                let outside: Bool
                switch axis {
                case 0: outside = value.x.lower > 0
                case 1: outside = value.x.upper < 0
                case 2: outside = value.y.lower > 0
                default: outside = value.y.upper < 0
                }
                if !outside { excluded = false; break scan }
            } }
            if excluded { return true }
        }
        return false
    }

    private func centerValue(using execution: inout OriginalQueryExecution) throws -> Vector {
        try evaluate(controlNet, using: &execution)
    }

    private func derivativeBounds(alongFirst: Bool, using execution: inout OriginalQueryExecution) throws -> Vector {
        try execution.consumeWork(1)
        let derivativeNet: [[Vector]]
        if alongFirst {
            let degree = OutwardScalarInterval.exact(Double(controlNet.count - 1))
            derivativeNet = try OriginalCoefficientAllocation.map(elements: 0..<(controlNet.count - 1), using: &execution) { firstIndex, execution in
                try OriginalCoefficientAllocation.map(elements: controlNet[firstIndex].indices, using: &execution) { secondIndex, _ in
                    Vector(x: (controlNet[firstIndex + 1][secondIndex].x - controlNet[firstIndex][secondIndex].x) * degree,
                        y: (controlNet[firstIndex + 1][secondIndex].y - controlNet[firstIndex][secondIndex].y) * degree)
                }
            }
        } else {
            let count = controlNet[0].count
            let degree = OutwardScalarInterval.exact(Double(count - 1))
            derivativeNet = try OriginalCoefficientAllocation.map(elements: controlNet.indices, using: &execution) { firstIndex, execution in
                try OriginalCoefficientAllocation.map(elements: 0..<(count - 1), using: &execution) { secondIndex, _ in
                    Vector(x: (controlNet[firstIndex][secondIndex + 1].x - controlNet[firstIndex][secondIndex].x) * degree,
                        y: (controlNet[firstIndex][secondIndex + 1].y - controlNet[firstIndex][secondIndex].y) * degree)
                }
            }
        }
        return try hull(derivativeNet, using: &execution)
    }

    private func hull(_ values: [[Vector]], using execution: inout OriginalQueryExecution) throws -> Vector {
        var first: Vector?
        var lowerX = 0.0, upperX = 0.0, lowerY = 0.0, upperY = 0.0
        for row in values { for value in row {
            try execution.consumeWork(1)
            if first == nil {
                first = value; lowerX = value.x.lower; upperX = value.x.upper
                lowerY = value.y.lower; upperY = value.y.upper
            } else {
                if value.x.lower < lowerX { lowerX = value.x.lower }
                if upperX < value.x.upper { upperX = value.x.upper }
                if value.y.lower < lowerY { lowerY = value.y.lower }
                if upperY < value.y.upper { upperY = value.y.upper }
            }
        } }
        guard first != nil else {
            return Vector(x: .init(lower: -.infinity, upper: .infinity), y: .init(lower: -.infinity, upper: .infinity))
        }
        return Vector(x: .init(lower: lowerX, upper: upperX), y: .init(lower: lowerY, upper: upperY))
    }

    private func evaluate(_ values: [[Vector]], using execution: inout OriginalQueryExecution) throws -> Vector {
        var firstReduced = values
        while firstReduced.count > 1 {
            try execution.consumeWork(1)
            firstReduced = try OriginalCoefficientAllocation.map(elements: 0..<(firstReduced.count - 1), using: &execution) { index, execution in
                try OriginalCoefficientAllocation.map(first: firstReduced[index], second: firstReduced[index + 1], using: &execution) { pair, _ in
                    pair.0.midpoint(with: pair.1)
                }
            }
        }
        var secondReduced = firstReduced[0]
        while secondReduced.count > 1 {
            try execution.consumeWork(1)
            secondReduced = try OriginalCoefficientAllocation.map(elements: 0..<(secondReduced.count - 1), using: &execution) { index, _ in
                secondReduced[index].midpoint(with: secondReduced[index + 1])
            }
        }
        return secondReduced[0]
    }

    private func split<T>(_ values: [T], parameter: Double,
        using execution: inout OriginalQueryExecution,
        interpolation: (T, T, OutwardScalarInterval, inout OriginalQueryExecution) throws -> T
    ) throws -> (lower: [T], upper: [T]) {
        let intervalParameter = OutwardScalarInterval.exact(parameter)
        try OriginalCoefficientAllocation.reserve(count: values.count, of: [T].self, using: &execution)
        var levels: [[T]] = []; levels.reserveCapacity(values.count); levels.append(values)
        while let previous = levels.last, previous.count > 1 {
            try execution.consumeWork(1)
            levels.append(try OriginalCoefficientAllocation.map(elements: 0..<(previous.count - 1), using: &execution) { index, execution in
                try interpolation(previous[index], previous[index + 1], intervalParameter, &execution)
            })
        }
        return (try OriginalCoefficientAllocation.map(elements: levels, using: &execution) { level, _ in level[0] },
            try OriginalCoefficientAllocation.map(elements: levels.reversed(), using: &execution) { level, _ in level[level.count - 1] })
    }

    private func restricted<T>(_ values: [T], from lower: Double, to upper: Double,
        using execution: inout OriginalQueryExecution,
        interpolation: (T, T, OutwardScalarInterval, inout OriginalQueryExecution) throws -> T
    ) throws -> [T] {
        try execution.consumeWork(1)
        var result = values
        if lower != 0 { result = try split(result, parameter: lower, using: &execution, interpolation: interpolation).upper }
        let localUpper = (upper - lower) / (1 - lower)
        if localUpper != 1 { result = try split(result, parameter: localUpper, using: &execution, interpolation: interpolation).lower }
        return result
    }

    private func restrictedFirst(_ values: [[Vector]], from lower: Double, to upper: Double,
        using execution: inout OriginalQueryExecution) throws -> [[Vector]] {
        try restricted(values, from: lower, to: upper, using: &execution) { first, second, parameter, execution in
            try OriginalCoefficientAllocation.map(first: first, second: second, using: &execution) { pair, _ in
                pair.0.interpolated(to: pair.1, parameter: parameter)
            }
        }
    }

    private func restrictedSecond(_ values: [[Vector]], from lower: Double, to upper: Double,
        using execution: inout OriginalQueryExecution) throws -> [[Vector]] {
        try OriginalCoefficientAllocation.map(elements: values, using: &execution) { row, execution in
            try restricted(row, from: lower, to: upper, using: &execution) { first, second, parameter, _ in
                first.interpolated(to: second, parameter: parameter)
            }
        }
    }

    private func positionEnclosure(controls: [HomogeneousPoint], normalizedParameter: OutwardScalarInterval,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> (x: OutwardScalarInterval, y: OutwardScalarInterval) {
        var level = controls
        while level.count > 1 {
            try execution.consumeWork(1)
            level = try OriginalCoefficientAllocation.map(elements: 0..<(level.count - 1), using: &execution) { index, _ in
                level[index].interpolated(to: level[index + 1], parameter: normalizedParameter)
            }
        }
        guard let value = level.first, let x = value.x.divided(by: value.weight), let y = value.y.divided(by: value.weight) else {
            throw Self.failure(.singularSystem, tolerance: tolerance,
                "Rational pcurve position enclosure crossed a non-positive denominator.")
        }
        return (x, y)
    }

    private func affineImage(
        _ normalized: OutwardScalarInterval,
        lower: Double,
        upper: Double
    ) -> OutwardScalarInterval {
        OutwardScalarInterval.exact(lower)
            + OutwardScalarInterval.exact(upper - lower) * normalized
    }

    private func scalarInterval(
        _ interval: OutwardScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard interval.isFinite else {
            throw Self.failure(
                .resourceLimitExceeded,
                tolerance: tolerance,
                "Rational pcurve certification exceeded finite interval representation."
            )
        }
        return try ScalarInterval(lower: interval.lower, upper: interval.upper)
    }

    private static func failure(
        _ code: KernelErrorCode,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: code,
            tolerance: tolerance,
            message: message
        )
    }
}
