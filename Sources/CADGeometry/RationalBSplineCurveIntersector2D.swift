import CADCore
import Foundation

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
    package func intersections(
        first: BSplineCurve2D,
        second: BSplineCurve2D,
        maximumSubdivisionDepth: Int,
        maximumSubdivisionCells: Int,
        accepting: (RationalBSplineCurveIntersection2D) throws -> Bool,
        tolerance: ModelingTolerance
    ) throws -> [RationalBSplineCurveIntersection2D] {
        try tolerance.validate()
        try first.validate(tolerance: tolerance)
        try second.validate(tolerance: tolerance)
        guard maximumSubdivisionDepth >= 0,
              maximumSubdivisionDepth <= 48,
              maximumSubdivisionCells > 0 else {
            throw failure(
                .resourceLimitExceeded,
                tolerance: tolerance,
                "Rational pcurve intersection limits are outside the supported resource envelope."
            )
        }

        let firstPatches = try first.rationalBezierPatches(tolerance: tolerance)
        let secondPatches = try second.rationalBezierPatches(tolerance: tolerance)
        var pending: [Cell] = []
        var result: [RationalBSplineCurveIntersection2D] = []
        pending.reserveCapacity(firstPatches.count * secondPatches.count)
        for firstPatch in firstPatches.reversed() {
            for secondPatch in secondPatches.reversed() {
                if let tangencies = try certifiedQuadraticLineTangencies(
                    first: firstPatch,
                    second: secondPatch,
                    tolerance: tolerance
                ) {
                    for tangency in tangencies {
                        guard try accepting(tangency) else {
                            throw failure(
                                .resourceLimitExceeded,
                                residual: tangency.pointEnclosure.maximumWidth,
                                tolerance: tolerance,
                                "A certified quadratic-line tangency did not satisfy the consumer precision contract."
                            )
                        }
                        appendUnique(tangency, to: &result)
                    }
                    continue
                }
                let patch = try DifferencePatch(
                    first: firstPatch,
                    second: secondPatch,
                    tolerance: tolerance
                )
                pending.append(Cell(
                    patch: patch.expandedForBoundaryCertification(),
                    depth: 0
                ))
            }
        }

        var remainingCells = maximumSubdivisionCells
        var acceptedRootDomains: [DifferencePatch] = []
        var unresolvedLeaves: [DifferencePatch] = []
        while let cell = pending.popLast() {
            if acceptedRootDomains.contains(where: {
                $0.containsParameterDomain(of: cell.patch)
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
            switch cell.patch.rootCertificate() {
            case .excluded:
                continue
            case let .unique(firstNormalized, secondNormalized):
                guard let candidate = try cell.patch.intersectionEnclosure(
                    firstNormalized: firstNormalized,
                    secondNormalized: secondNormalized,
                    tolerance: tolerance
                ) else { continue }
                if try accepting(candidate) {
                    appendUnique(candidate, to: &result)
                    acceptedRootDomains.append(cell.patch)
                    continue
                }
                guard cell.depth < maximumSubdivisionDepth else {
                    if cell.patch.intersectsOriginalParameterDomain {
                        unresolvedLeaves.append(cell.patch)
                    }
                    continue
                }
                pending.append(Cell(
                    patch: cell.patch.refinedAroundUniqueRoot(
                        firstNormalized: firstNormalized,
                        secondNormalized: secondNormalized
                    ),
                    depth: cell.depth + 1
                ))
                continue
            case .unresolved:
                break
            }

            guard cell.depth < maximumSubdivisionDepth else {
                if cell.patch.intersectsOriginalParameterDomain {
                    unresolvedLeaves.append(cell.patch)
                }
                continue
            }
            for child in cell.patch.subdivided().reversed() {
                pending.append(Cell(patch: child, depth: cell.depth + 1))
            }
        }
        if let unresolved = unresolvedLeaves.first(where: { leaf in
            acceptedRootDomains.contains(where: {
                $0.containsParameterDomain(of: leaf)
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
        return result.sorted {
            if $0.firstParameterEnclosure.midpoint
                != $1.firstParameterEnclosure.midpoint {
                return $0.firstParameterEnclosure.midpoint
                    < $1.firstParameterEnclosure.midpoint
            }
            return $0.secondParameterEnclosure.midpoint
                < $1.secondParameterEnclosure.midpoint
        }
    }

    private func appendUnique(
        _ intersection: RationalBSplineCurveIntersection2D,
        to result: inout [RationalBSplineCurveIntersection2D]
    ) {
        guard let index = result.firstIndex(where: {
            $0.firstParameterEnclosure.intersects(
                intersection.firstParameterEnclosure
            ) && $0.secondParameterEnclosure.intersects(
                intersection.secondParameterEnclosure
            )
        }) else {
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
    ) throws -> [RationalBSplineCurveIntersection2D]? {
        if first.degree == 2, second.degree == 1 {
            return try certifiedQuadraticLineTangencies(
                quadratic: first,
                line: second,
                quadraticIsFirst: true,
                tolerance: tolerance
            )
        }
        if first.degree == 1, second.degree == 2 {
            return try certifiedQuadraticLineTangencies(
                quadratic: second,
                line: first,
                quadraticIsFirst: false,
                tolerance: tolerance
            )
        }
        return nil
    }

    private func certifiedQuadraticLineTangencies(
        quadratic: RationalBezierCurvePatch2D,
        line: RationalBezierCurvePatch2D,
        quadraticIsFirst: Bool,
        tolerance: ModelingTolerance
    ) throws -> [RationalBSplineCurveIntersection2D]? {
        guard quadratic.controlPoints.count == 3,
              quadratic.weights.count == 3,
              line.controlPoints.count == 2,
              line.weights.count == 2 else {
            return nil
        }
        let start = line.controlPoints[0]
        let end = line.controlPoints[1]
        let lineA = ExactExpansionArithmetic.subtract([start.y], [end.y])
        let lineB = ExactExpansionArithmetic.subtract([end.x], [start.x])
        let lineC = ExactExpansionArithmetic.subtract(
            ExactExpansionArithmetic.multiply([start.x], [end.y]),
            ExactExpansionArithmetic.multiply([end.x], [start.y])
        )
        let bernstein = quadratic.controlPoints.indices.map { index in
            let weight = quadratic.weights[index]
            let point = quadratic.controlPoints[index]
            let homogeneousX = ExactExpansionArithmetic.multiply(
                [point.x],
                [weight]
            )
            let homogeneousY = ExactExpansionArithmetic.multiply(
                [point.y],
                [weight]
            )
            return ExactExpansionArithmetic.add(
                ExactExpansionArithmetic.add(
                    ExactExpansionArithmetic.multiply(lineA, homogeneousX),
                    ExactExpansionArithmetic.multiply(lineB, homogeneousY)
                ),
                ExactExpansionArithmetic.multiply(lineC, [weight])
            )
        }
        let constant = bernstein[0]
        let linear = ExactExpansionArithmetic.multiply(
            ExactExpansionArithmetic.subtract(bernstein[1], bernstein[0]),
            [2.0]
        )
        let quadraticCoefficient = ExactExpansionArithmetic.add(
            ExactExpansionArithmetic.subtract(
                bernstein[0],
                ExactExpansionArithmetic.multiply(bernstein[1], [2.0])
            ),
            bernstein[2]
        )
        guard ExactExpansionArithmetic.sign(quadraticCoefficient) != .zero else {
            return nil
        }
        let discriminant = ExactExpansionArithmetic.subtract(
            ExactExpansionArithmetic.multiply(linear, linear),
            ExactExpansionArithmetic.multiply(
                [4.0],
                ExactExpansionArithmetic.multiply(
                    quadraticCoefficient,
                    constant
                )
            )
        )
        guard ExactExpansionArithmetic.sign(discriminant) == .zero else {
            return nil
        }
        let numerator = -expansionEnclosure(linear)
        let denominator = expansionEnclosure(
            ExactExpansionArithmetic.multiply(quadraticCoefficient, [2.0])
        )
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
        )
        let lineParameter = try lineParameterEnclosure(
            for: quadraticPosition,
            line: line,
            tolerance: tolerance
        )
        guard let boundedLineParameter = lineParameter.intersection(
            with: OutwardScalarInterval(lower: 0.0, upper: 1.0)
        ) else {
            return []
        }
        let linePosition = try rationalPositionEnclosure(
            line,
            parameter: boundedLineParameter,
            tolerance: tolerance
        )
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
        return [RationalBSplineCurveIntersection2D(
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
        )]
    }

    private func expansionEnclosure(
        _ expansion: ExactExpansionArithmetic.Scalar
    ) -> OutwardScalarInterval {
        expansion.reduce(.exact(0.0)) {
            $0 + .exact($1)
        }
    }

    private func rationalPositionEnclosure(
        _ patch: RationalBezierCurvePatch2D,
        parameter: OutwardScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> (x: OutwardScalarInterval, y: OutwardScalarInterval) {
        var x = patch.controlPoints.indices.map {
            OutwardScalarInterval.exact(patch.controlPoints[$0].x)
                * .exact(patch.weights[$0])
        }
        var y = patch.controlPoints.indices.map {
            OutwardScalarInterval.exact(patch.controlPoints[$0].y)
                * .exact(patch.weights[$0])
        }
        var weights = patch.weights.map(OutwardScalarInterval.exact)
        let complement = OutwardScalarInterval.exact(1.0) - parameter
        while x.count > 1 {
            x = zip(x, x.dropFirst()).map {
                $0 * complement + $1 * parameter
            }
            y = zip(y, y.dropFirst()).map {
                $0 * complement + $1 * parameter
            }
            weights = zip(weights, weights.dropFirst()).map {
                $0 * complement + $1 * parameter
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
    ) throws -> OutwardScalarInterval {
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
    ) throws {
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
        let firstControls = first.controlPoints.indices.map {
            HomogeneousPoint(
                point: first.controlPoints[$0],
                weight: first.weights[$0]
            )
        }
        let secondControls = second.controlPoints.indices.map {
            HomogeneousPoint(
                point: second.controlPoints[$0],
                weight: second.weights[$0]
            )
        }
        guard firstControls.allSatisfy(\.isFiniteAndPositive),
              secondControls.allSatisfy(\.isFiniteAndPositive) else {
            throw Self.failure(
                .resourceLimitExceeded,
                tolerance: tolerance,
                "Rational pcurve homogeneous controls exceeded finite positive interval arithmetic."
            )
        }
        let controlNet = Self.differenceControlNet(
            first: firstControls,
            second: secondControls
        )
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
        guard controlNet.flatMap({ $0 }).allSatisfy(\.isFinite) else {
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

    func rootCertificate() -> RootCertificate {
        guard excludesZero() == false else { return .excluded }
        let value = centerValue()
        let firstDerivative = derivativeBounds(alongFirst: true)
        let secondDerivative = derivativeBounds(alongFirst: false)
        let a = firstDerivative.x.midpoint
        let b = secondDerivative.x.midpoint
        let c = firstDerivative.y.midpoint
        let d = secondDerivative.y.midpoint
        let determinant = a * d - b * c
        guard determinant.isFinite, determinant != 0.0 else {
            return .unresolved
        }
        let inverse = [
            [d / determinant, -b / determinant],
            [-c / determinant, a / determinant],
        ]
        guard inverse.flatMap({ $0 }).allSatisfy(\.isFinite) else {
            return .unresolved
        }
        let jacobian = [
            [firstDerivative.x, secondDerivative.x],
            [firstDerivative.y, secondDerivative.y],
        ]
        let functionValue = [value.x, value.y]
        let unit = OutwardScalarInterval(lower: 0.0, upper: 1.0)
        let radius = OutwardScalarInterval(lower: -0.5, upper: 0.5)
        var image: [OutwardScalarInterval] = []
        for row in 0..<2 {
            var component = OutwardScalarInterval.exact(0.5)
            for inner in 0..<2 {
                component = component
                    - OutwardScalarInterval(inverse[row][inner])
                        * functionValue[inner]
            }
            for column in 0..<2 {
                var preconditioned = OutwardScalarInterval.exact(0.0)
                for inner in 0..<2 {
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
        if image.contains(where: { $0.intersection(with: unit) == nil }) {
            return .excluded
        }
        if image.allSatisfy({ $0.isStrictlyInside(unit) }) {
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
    ) throws -> RationalBSplineCurveIntersection2D? {
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
        )
        let secondPosition = try positionEnclosure(
            controls: sourceSecondControls,
            normalizedParameter: boundedSecondSourceParameters,
            tolerance: tolerance
        )
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

    func subdivided() -> [DifferencePatch] {
        // This is a proof-domain overlap, not a modeling tolerance. Both
        // children contain the shared split in their strict interior so a
        // root on an artificial subdivision boundary remains certifiable.
        let overlap = 1.0 / 64.0
        if firstUpper - firstLower >= secondUpper - secondLower {
            return [
                restrictedFirst(from: 0.0, to: 0.5 + overlap),
                restrictedFirst(from: 0.5 - overlap, to: 1.0),
            ]
        }
        return [
            restrictedSecond(from: 0.0, to: 0.5 + overlap),
            restrictedSecond(from: 0.5 - overlap, to: 1.0),
        ]
    }

    func expandedForBoundaryCertification() -> DifferencePatch {
        let extensionFraction = 1.0 / 64.0
        let lower = -extensionFraction
        let upper = 1.0 + extensionFraction
        let firstControls = restricted(
            sourceFirstControls,
            from: lower,
            to: upper
        ) { first, second, parameter in
            first.interpolated(to: second, parameter: parameter)
        }
        let secondControls = restricted(
            sourceSecondControls,
            from: lower,
            to: upper
        ) { first, second, parameter in
            first.interpolated(to: second, parameter: parameter)
        }
        guard firstControls.allSatisfy(\.isFiniteAndPositive),
              secondControls.allSatisfy(\.isFiniteAndPositive) else {
            return self
        }
        return restrictedDomain(
            firstLower: lower,
            firstUpper: upper,
            secondLower: lower,
            secondUpper: upper
        )
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
    ) -> DifferencePatch {
        let firstRange = paddedRootRange(firstNormalized)
        let secondRange = paddedRootRange(secondNormalized)
        return restrictedFirst(from: firstRange.lower, to: firstRange.upper)
            .restrictedSecond(
                from: secondRange.lower,
                to: secondRange.upper
            )
    }

    private func paddedRootRange(
        _ root: OutwardScalarInterval
    ) -> OutwardScalarInterval {
        let padding = max(root.width, Double.ulpOfOne)
        return OutwardScalarInterval(
            lower: max(0.0, (root.lower - padding).nextDown),
            upper: min(1.0, (root.upper + padding).nextUp)
        )
    }

    private func restrictedFirst(
        from lowerFraction: Double,
        to upperFraction: Double
    ) -> DifferencePatch {
        let span = firstSourceDomainUpper - firstSourceDomainLower
        return restrictedDomain(
            firstLower: firstSourceDomainLower + span * lowerFraction,
            firstUpper: firstSourceDomainLower + span * upperFraction,
            secondLower: secondSourceDomainLower,
            secondUpper: secondSourceDomainUpper
        )
    }

    private func restrictedSecond(
        from lowerFraction: Double,
        to upperFraction: Double
    ) -> DifferencePatch {
        let span = secondSourceDomainUpper - secondSourceDomainLower
        return restrictedDomain(
            firstLower: firstSourceDomainLower,
            firstUpper: firstSourceDomainUpper,
            secondLower: secondSourceDomainLower + span * lowerFraction,
            secondUpper: secondSourceDomainLower + span * upperFraction
        )
    }

    private func restrictedDomain(
        firstLower: Double,
        firstUpper: Double,
        secondLower: Double,
        secondUpper: Double
    ) -> DifferencePatch {
        let firstRestrictedNet = restrictedFirst(
            sourceControlNet,
            from: firstLower,
            to: firstUpper
        )
        let currentControlNet = restrictedSecond(
            firstRestrictedNet,
            from: secondLower,
            to: secondUpper
        )
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

    private static func differenceControlNet(
        first: [HomogeneousPoint],
        second: [HomogeneousPoint]
    ) -> [[Vector]] {
        first.map { firstControl in
            second.map { secondControl in
                Vector(
                    x: firstControl.x * secondControl.weight
                        - secondControl.x * firstControl.weight,
                    y: firstControl.y * secondControl.weight
                        - secondControl.y * firstControl.weight
                )
            }
        }
    }

    private func excludesZero() -> Bool {
        let values = controlNet.flatMap { $0 }
        return values.allSatisfy { $0.x.lower > 0.0 }
            || values.allSatisfy { $0.x.upper < 0.0 }
            || values.allSatisfy { $0.y.lower > 0.0 }
            || values.allSatisfy { $0.y.upper < 0.0 }
    }

    private func centerValue() -> Vector {
        evaluate(controlNet)
    }

    private func derivativeBounds(alongFirst: Bool) -> Vector {
        let derivativeNet: [[Vector]]
        if alongFirst {
            let degree = OutwardScalarInterval.exact(
                Double(controlNet.count - 1)
            )
            derivativeNet = (0..<(controlNet.count - 1)).map { firstIndex in
                controlNet[firstIndex].indices.map { secondIndex in
                    Vector(
                        x: (
                            controlNet[firstIndex + 1][secondIndex].x
                                - controlNet[firstIndex][secondIndex].x
                        ) * degree,
                        y: (
                            controlNet[firstIndex + 1][secondIndex].y
                                - controlNet[firstIndex][secondIndex].y
                        ) * degree
                    )
                }
            }
        } else {
            let count = controlNet[0].count
            let degree = OutwardScalarInterval.exact(Double(count - 1))
            derivativeNet = controlNet.indices.map { firstIndex in
                (0..<(count - 1)).map { secondIndex in
                    Vector(
                        x: (
                            controlNet[firstIndex][secondIndex + 1].x
                                - controlNet[firstIndex][secondIndex].x
                        ) * degree,
                        y: (
                            controlNet[firstIndex][secondIndex + 1].y
                                - controlNet[firstIndex][secondIndex].y
                        ) * degree
                    )
                }
            }
        }
        return hull(derivativeNet)
    }

    private func hull(_ values: [[Vector]]) -> Vector {
        let flat = values.flatMap { $0 }
        return Vector(
            x: .enclosing(flat.map(\.x)),
            y: .enclosing(flat.map(\.y))
        )
    }

    private func evaluate(_ values: [[Vector]]) -> Vector {
        var firstReduced = values
        while firstReduced.count > 1 {
            firstReduced = (0..<(firstReduced.count - 1)).map { index in
                zip(firstReduced[index], firstReduced[index + 1]).map {
                    $0.midpoint(with: $1)
                }
            }
        }
        var secondReduced = firstReduced[0]
        while secondReduced.count > 1 {
            secondReduced = (0..<(secondReduced.count - 1)).map { index in
                secondReduced[index].midpoint(with: secondReduced[index + 1])
            }
        }
        return secondReduced[0]
    }

    private func split<T>(
        _ values: [T],
        parameter: Double,
        interpolation: (T, T, OutwardScalarInterval) -> T
    ) -> (lower: [T], upper: [T]) {
        let intervalParameter = OutwardScalarInterval.exact(parameter)
        var levels = [values]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                interpolation(
                    previous[index],
                    previous[index + 1],
                    intervalParameter
                )
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }

    private func restricted<T>(
        _ values: [T],
        from lower: Double,
        to upper: Double,
        interpolation: (T, T, OutwardScalarInterval) -> T
    ) -> [T] {
        var result = values
        if lower != 0.0 {
            result = split(
                result,
                parameter: lower,
                interpolation: interpolation
            ).upper
        }
        let localUpper = (upper - lower) / (1.0 - lower)
        if localUpper != 1.0 {
            result = split(
                result,
                parameter: localUpper,
                interpolation: interpolation
            ).lower
        }
        return result
    }

    private func restrictedFirst(
        _ values: [[Vector]],
        from lower: Double,
        to upper: Double
    ) -> [[Vector]] {
        restricted(values, from: lower, to: upper) {
            first, second, parameter in
            zip(first, second).map {
                $0.interpolated(to: $1, parameter: parameter)
            }
        }
    }

    private func restrictedSecond(
        _ values: [[Vector]],
        from lower: Double,
        to upper: Double
    ) -> [[Vector]] {
        values.map { row in
            restricted(row, from: lower, to: upper) {
                $0.interpolated(to: $1, parameter: $2)
            }
        }
    }

    private func positionEnclosure(
        controls: [HomogeneousPoint],
        normalizedParameter: OutwardScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> (x: OutwardScalarInterval, y: OutwardScalarInterval) {
        var level = controls
        while level.count > 1 {
            level = (0..<(level.count - 1)).map { index in
                level[index].interpolated(
                    to: level[index + 1],
                    parameter: normalizedParameter
                )
            }
        }
        guard let value = level.first,
              let x = value.x.divided(by: value.weight),
              let y = value.y.divided(by: value.weight) else {
            throw Self.failure(
                .singularSystem,
                tolerance: tolerance,
                "Rational pcurve position enclosure crossed a non-positive denominator."
            )
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
