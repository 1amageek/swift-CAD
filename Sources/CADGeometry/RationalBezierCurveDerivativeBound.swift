import CADCore
import Foundation
import Synchronization

package struct RationalBezierCurveDerivativeBound: Sendable {
    package let first: [Double]
    package let second: [Double]
    package let third: [Double]

    package init(
        coordinates: [[Double]],
        weights: [Double],
        parameterWidth: Double,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard coordinates.isEmpty == false,
              coordinates.allSatisfy({ $0.count == weights.count }),
              weights.count >= 2,
              weights.allSatisfy({ $0.isFinite && $0 > Double.ulpOfOne }),
              parameterWidth.isFinite,
              parameterWidth > Double.ulpOfOne else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational Bezier derivative bounds require a positive finite patch."
            )
        }
        let degree = weights.count - 1
        let minimumWeight = (weights.min() ?? 0.0).nextDown
        guard minimumWeight > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: minimumWeight,
                tolerance: tolerance,
                message: "Rational Bezier derivative bounds require a positive weight enclosure."
            )
        }
        if let certificate = RationalBezierCurveDerivativeCertificate(
            coordinates: coordinates,
            weights: weights,
            parameterWidth: parameterWidth
        ), let correlated = try certificate.allDerivativeBounds() {
            first = correlated.first
            second = correlated.second
            third = correlated.third
            return
        }
        let weightFirst = Self.firstDerivativeControlBound(
            weights,
            degree: degree
        )
        let weightSecond = Self.secondDerivativeControlBound(
            weights,
            degree: degree
        )
        let weightThird = Self.thirdDerivativeControlBound(
            weights,
            degree: degree
        )
        let firstScale = Self.upwardDivide(1.0, parameterWidth)
        let secondScale = Self.upwardProduct(firstScale, firstScale)
        let thirdScale = Self.upwardProduct(secondScale, firstScale)
        var firstResult: [Double] = []
        var secondResult: [Double] = []
        var thirdResult: [Double] = []
        firstResult.reserveCapacity(coordinates.count)
        secondResult.reserveCapacity(coordinates.count)
        thirdResult.reserveCapacity(coordinates.count)
        for coordinate in coordinates {
            let homogeneous = coordinate.indices.map {
                coordinate[$0] * weights[$0]
            }
            guard homogeneous.allSatisfy(\.isFinite) else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Rational Bezier derivative bounds exceeded finite homogeneous arithmetic."
                )
            }
            let value = Self.maximumAbsolute(homogeneous)
            let numeratorFirst = Self.firstDerivativeControlBound(
                homogeneous,
                degree: degree
            )
            let numeratorSecond = Self.secondDerivativeControlBound(
                homogeneous,
                degree: degree
            )
            let numeratorThird = Self.thirdDerivativeControlBound(
                homogeneous,
                degree: degree
            )
            let minimumWeightSquared = (
                minimumWeight * minimumWeight
            ).nextDown
            let minimumWeightCubed = (
                minimumWeightSquared * minimumWeight
            ).nextDown
            let minimumWeightFourth = (
                minimumWeightCubed * minimumWeight
            ).nextDown
            guard minimumWeightSquared > 0.0,
                  minimumWeightCubed > 0.0,
                  minimumWeightFourth > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: minimumWeightCubed,
                    tolerance: tolerance,
                    message: "Rational Bezier derivative weight bounds underflowed."
                )
            }
            let firstLocal = Self.upwardSum(
                Self.upwardDivide(numeratorFirst, minimumWeight),
                Self.upwardDivide(
                    Self.upwardProduct(value, weightFirst),
                    minimumWeightSquared
                )
            )
            let secondLocal = Self.upwardSum(
                Self.upwardDivide(numeratorSecond, minimumWeight),
                Self.upwardSum(
                    Self.upwardDivide(
                        Self.upwardProduct(
                            2.0,
                            Self.upwardProduct(numeratorFirst, weightFirst)
                        ),
                        minimumWeightSquared
                    ),
                    Self.upwardSum(
                        Self.upwardDivide(
                            Self.upwardProduct(value, weightSecond),
                            minimumWeightSquared
                        ),
                        Self.upwardDivide(
                            Self.upwardProduct(
                                2.0,
                                Self.upwardProduct(
                                    value,
                                    Self.upwardProduct(weightFirst, weightFirst)
                                )
                            ),
                            minimumWeightCubed
                        )
                    )
                )
            )
            firstResult.append(Self.upwardProduct(firstLocal, firstScale))
            secondResult.append(Self.upwardProduct(secondLocal, secondScale))
            let thirdLocal = Self.upwardSum(
                Self.upwardDivide(numeratorThird, minimumWeight),
                Self.upwardSum(
                    Self.upwardDivide(
                        Self.upwardProduct(3.0, Self.upwardProduct(numeratorSecond, weightFirst)),
                        minimumWeightSquared
                    ),
                    Self.upwardSum(
                        Self.upwardDivide(
                            Self.upwardProduct(3.0, Self.upwardProduct(numeratorFirst, weightSecond)),
                            minimumWeightSquared
                        ),
                        Self.upwardSum(
                            Self.upwardDivide(
                                Self.upwardProduct(
                                    6.0,
                                    Self.upwardProduct(
                                        numeratorFirst,
                                        Self.upwardProduct(weightFirst, weightFirst)
                                    )
                                ),
                                minimumWeightCubed
                            ),
                            Self.upwardSum(
                                Self.upwardDivide(
                                    Self.upwardProduct(value, weightThird),
                                    minimumWeightSquared
                                ),
                                Self.upwardSum(
                                    Self.upwardDivide(
                                        Self.upwardProduct(
                                            6.0,
                                            Self.upwardProduct(
                                                value,
                                                Self.upwardProduct(weightFirst, weightSecond)
                                            )
                                        ),
                                        minimumWeightCubed
                                    ),
                                    Self.upwardDivide(
                                        Self.upwardProduct(
                                            6.0,
                                            Self.upwardProduct(
                                                value,
                                                Self.upwardProduct(
                                                    weightFirst,
                                                    Self.upwardProduct(weightFirst, weightFirst)
                                                )
                                            )
                                        ),
                                        minimumWeightFourth
                                    )
                                )
                            )
                        )
                    )
                )
            )
            thirdResult.append(Self.upwardProduct(thirdLocal, thirdScale))
        }
        first = firstResult
        second = secondResult
        third = thirdResult
    }

    private static func firstDerivativeControlBound(
        _ values: [Double],
        degree: Int
    ) -> Double {
        guard degree > 0 else { return 0.0 }
        var maximum = 0.0
        for index in 0..<degree {
            maximum = max(
                maximum,
                abs(values[index + 1] - values[index]).nextUp
            )
        }
        return upwardProduct(Double(degree), maximum)
    }

    private static func secondDerivativeControlBound(
        _ values: [Double],
        degree: Int
    ) -> Double {
        guard degree > 1 else { return 0.0 }
        var maximum = 0.0
        for index in 0..<(degree - 1) {
            let firstDifference = values[index + 2] - values[index + 1]
            let secondDifference = values[index + 1] - values[index]
            let difference = firstDifference - secondDifference
            let scale = max(
                abs(values[index]),
                abs(values[index + 1]),
                abs(values[index + 2]),
                1.0
            )
            let arithmeticAllowance = (
                Double.ulpOfOne * scale * 32.0
            ).nextUp
            maximum = max(
                maximum,
                (abs(difference) + arithmeticAllowance).nextUp
            )
        }
        return upwardProduct(
            Double(degree * (degree - 1)),
            maximum
        )
    }

    private static func thirdDerivativeControlBound(
        _ values: [Double],
        degree: Int
    ) -> Double {
        guard degree > 2 else { return 0.0 }
        var maximum = 0.0
        for index in 0..<(degree - 2) {
            let difference = values[index + 3]
                - 3.0 * values[index + 2]
                + 3.0 * values[index + 1]
                - values[index]
            let scale = max(
                abs(values[index]),
                abs(values[index + 1]),
                abs(values[index + 2]),
                abs(values[index + 3]),
                1.0
            )
            let arithmeticAllowance = (
                Double.ulpOfOne * scale * 64.0
            ).nextUp
            maximum = max(
                maximum,
                (abs(difference) + arithmeticAllowance).nextUp
            )
        }
        return upwardProduct(
            Double(degree * (degree - 1) * (degree - 2)),
            maximum
        )
    }

    private static func maximumAbsolute(_ values: [Double]) -> Double {
        (values.map(abs).max() ?? 0.0).nextUp
    }

    private static func upwardSum(_ lhs: Double, _ rhs: Double) -> Double {
        (lhs + rhs).nextUp
    }

    private static func upwardProduct(_ lhs: Double, _ rhs: Double) -> Double {
        (lhs * rhs).nextUp
    }

    private static func upwardDivide(_ lhs: Double, _ rhs: Double) -> Double {
        (lhs / rhs).nextUp
    }
}

/// A reusable certificate for rational Bezier derivatives. It preserves the
/// algebraic correlation in the quotient-rule numerators and lets recursive
/// algorithms restrict already-built Bernstein polynomials instead of
/// rebuilding products at every subdivision interval.
package struct RationalBezierCurveDerivativeCertificate: Sendable {
    private let restrictionCache: any RationalBezierDerivativeRestrictionCaching

    package init?(
        curve: BSplineCurve3D
    ) {
        guard curve.controlPointCount == curve.degree + 1,
              curve.knots.count == 2 * (curve.degree + 1),
              case let .closed(lower, upper) = curve.domain,
              curve.knots.prefix(curve.degree + 1).allSatisfy({ $0 == lower }),
              curve.knots.suffix(curve.degree + 1).allSatisfy({ $0 == upper }) else {
            return nil
        }
        self.init(
            coordinates: [
                curve.controlPoints.map(\.x),
                curve.controlPoints.map(\.y),
                curve.controlPoints.map(\.z),
            ],
            weights: curve.weights,
            parameterWidth: upper - lower
        )
    }

    init?(
        coordinates: [[Double]],
        weights: [Double],
        parameterWidth: Double
    ) {
        guard coordinates.isEmpty == false,
              coordinates.allSatisfy({ $0.count == weights.count }),
              weights.count >= 2,
              weights.allSatisfy({ $0.isFinite && $0 > Double.ulpOfOne }),
              parameterWidth.isFinite,
              parameterWidth > Double.ulpOfOne,
              let weight = BernsteinIntervalPolynomial(values: weights),
              let weightFirst = weight.derivative(parameterWidth: parameterWidth) else {
            return nil
        }
        var firstNumerators: [BernsteinIntervalPolynomial] = []
        var secondNumerators: [BernsteinIntervalPolynomial] = []
        var thirdNumerators: [BernsteinIntervalPolynomial] = []
        firstNumerators.reserveCapacity(coordinates.count)
        secondNumerators.reserveCapacity(coordinates.count)
        thirdNumerators.reserveCapacity(coordinates.count)
        for coordinate in coordinates {
            guard let reference = coordinate.first,
                  coordinate.count == weights.count else {
                return nil
            }
            let homogeneous = coordinate.indices.map { index in
                OutwardScalarInterval(coordinate[index] - reference)
                    * OutwardScalarInterval(weights[index])
            }
            guard let numerator = BernsteinIntervalPolynomial(coefficients: homogeneous),
                  let numeratorFirst = numerator.derivative(parameterWidth: parameterWidth),
                  let firstNumerator = numeratorFirst.multiplied(by: weight)?
                    .subtracting(numerator.multiplied(by: weightFirst)),
                  let firstNumeratorDerivative = firstNumerator.derivative(
                    parameterWidth: parameterWidth
                  ),
                  let secondNumerator = firstNumeratorDerivative.multiplied(by: weight)?
                    .subtracting(
                        firstNumerator.multiplied(by: weightFirst)?.scaled(by: 2.0)
                    ),
                  let secondNumeratorDerivative = secondNumerator.derivative(
                    parameterWidth: parameterWidth
                  ),
                  let thirdNumerator = secondNumeratorDerivative.multiplied(by: weight)?
                    .subtracting(
                        secondNumerator.multiplied(by: weightFirst)?.scaled(by: 3.0)
                    ) else {
                return nil
            }
            firstNumerators.append(firstNumerator)
            secondNumerators.append(secondNumerator)
            thirdNumerators.append(thirdNumerator)
        }
        let roots: RationalBezierDerivativeRoots = [
            .first: RationalBezierRestrictedDerivativePolynomials(
                weight: weight,
                numerators: firstNumerators
            ),
            .second: RationalBezierRestrictedDerivativePolynomials(
                weight: weight,
                numerators: secondNumerators
            ),
            .third: RationalBezierRestrictedDerivativePolynomials(
                weight: weight,
                numerators: thirdNumerators
            ),
        ]
        if #available(macOS 15.0, iOS 18.0, visionOS 2.0, *) {
            restrictionCache = MutexRationalBezierDerivativeRestrictionCache(
                roots: roots
            )
        } else {
            restrictionCache = StatelessRationalBezierDerivativeRestrictionCache(
                roots: roots
            )
        }
    }

    package func firstDerivativeBounds(
        over interval: ScalarInterval
    ) -> [Double]? {
        derivativeBounds(
            order: .first,
            denominatorPower: 2,
            interval: interval
        )
    }

    package func secondDerivativeBounds(
        over interval: ScalarInterval
    ) -> [Double]? {
        derivativeBounds(
            order: .second,
            denominatorPower: 3,
            interval: interval
        )
    }

    package func thirdDerivativeBounds(
        over interval: ScalarInterval
    ) -> [Double]? {
        derivativeBounds(
            order: .third,
            denominatorPower: 4,
            interval: interval
        )
    }

    fileprivate func allDerivativeBounds() throws -> (
        first: [Double],
        second: [Double],
        third: [Double]
    )? {
        let interval = try ScalarInterval(lower: 0.0, upper: 1.0)
        guard let first = firstDerivativeBounds(over: interval),
              let second = secondDerivativeBounds(over: interval),
              let third = thirdDerivativeBounds(over: interval) else {
            return nil
        }
        return (first, second, third)
    }

    private func derivativeBounds(
        order: RationalBezierDerivativeOrder,
        denominatorPower: Int,
        interval: ScalarInterval
    ) -> [Double]? {
        guard interval.lower >= 0.0,
              interval.upper <= 1.0,
              interval.width > 0.0,
              let restricted = restrictionCache.restricted(
                order: order,
                to: interval
              ) else {
            return nil
        }
        let minimumWeight = restricted.weight.minimumLowerBound
        guard minimumWeight > 0.0 else { return nil }
        var denominator = 1.0
        for _ in 0..<denominatorPower {
            denominator = (denominator * minimumWeight).nextDown
        }
        guard denominator.isFinite, denominator > 0.0 else { return nil }
        var result: [Double] = []
        result.reserveCapacity(restricted.numerators.count)
        for numerator in restricted.numerators {
            let bound = (numerator.absoluteUpperBound / denominator).nextUp
            guard bound.isFinite else { return nil }
            result.append(bound)
        }
        return result
    }
}

private enum RationalBezierDerivativeOrder: Int, Hashable, Sendable {
    case first
    case second
    case third
}

private struct RationalBezierRestrictedDerivativePolynomials: Sendable {
    let weight: BernsteinIntervalPolynomial
    let numerators: [BernsteinIntervalPolynomial]

    func splitAtMidpoint() -> (
        left: RationalBezierRestrictedDerivativePolynomials,
        right: RationalBezierRestrictedDerivativePolynomials
    )? {
        guard let weightSplit = weight.split(at: 0.5) else { return nil }
        var leftNumerators: [BernsteinIntervalPolynomial] = []
        var rightNumerators: [BernsteinIntervalPolynomial] = []
        leftNumerators.reserveCapacity(numerators.count)
        rightNumerators.reserveCapacity(numerators.count)
        for numerator in numerators {
            guard let split = numerator.split(at: 0.5) else { return nil }
            leftNumerators.append(split.left)
            rightNumerators.append(split.right)
        }
        return (
            RationalBezierRestrictedDerivativePolynomials(
                weight: weightSplit.left,
                numerators: leftNumerators
            ),
            RationalBezierRestrictedDerivativePolynomials(
                weight: weightSplit.right,
                numerators: rightNumerators
            )
        )
    }

    func restricted(
        to interval: ScalarInterval
    ) -> RationalBezierRestrictedDerivativePolynomials? {
        guard let weight = weight.restricted(to: interval) else { return nil }
        var restrictedNumerators: [BernsteinIntervalPolynomial] = []
        restrictedNumerators.reserveCapacity(numerators.count)
        for numerator in numerators {
            guard let restricted = numerator.restricted(to: interval) else {
                return nil
            }
            restrictedNumerators.append(restricted)
        }
        return RationalBezierRestrictedDerivativePolynomials(
            weight: weight,
            numerators: restrictedNumerators
        )
    }
}

private struct RationalBezierDerivativeRestrictionKey: Hashable, Sendable {
    let order: RationalBezierDerivativeOrder
    let lowerBitPattern: UInt64
    let upperBitPattern: UInt64

    init(order: RationalBezierDerivativeOrder, lower: Double, upper: Double) {
        self.order = order
        lowerBitPattern = lower.bitPattern
        upperBitPattern = upper.bitPattern
    }
}

private typealias RationalBezierDerivativeRoots = [
    RationalBezierDerivativeOrder:
        RationalBezierRestrictedDerivativePolynomials
]

private protocol RationalBezierDerivativeRestrictionCaching: Sendable {
    func restricted(
        order: RationalBezierDerivativeOrder,
        to interval: ScalarInterval
    ) -> RationalBezierRestrictedDerivativePolynomials?
}

private final class StatelessRationalBezierDerivativeRestrictionCache:
    RationalBezierDerivativeRestrictionCaching,
    Sendable
{
    private let roots: RationalBezierDerivativeRoots

    init(roots: RationalBezierDerivativeRoots) {
        self.roots = roots
    }

    func restricted(
        order: RationalBezierDerivativeOrder,
        to interval: ScalarInterval
    ) -> RationalBezierRestrictedDerivativePolynomials? {
        roots[order]?.restricted(to: interval)
    }
}

@available(macOS 15.0, iOS 18.0, visionOS 2.0, *)
private final class MutexRationalBezierDerivativeRestrictionCache:
    RationalBezierDerivativeRestrictionCaching,
    Sendable
{
    private struct State: Sendable {
        var restrictions: [
            RationalBezierDerivativeRestrictionKey:
                RationalBezierRestrictedDerivativePolynomials
        ]
    }

    private let roots: RationalBezierDerivativeRoots
    private let state: Mutex<State>

    init(roots: RationalBezierDerivativeRoots) {
        self.roots = roots
        var restrictions: [
            RationalBezierDerivativeRestrictionKey:
                RationalBezierRestrictedDerivativePolynomials
        ] = [:]
        for (order, root) in roots {
            restrictions[
                RationalBezierDerivativeRestrictionKey(
                    order: order,
                    lower: 0.0,
                    upper: 1.0
                )
            ] = root
        }
        state = Mutex(State(restrictions: restrictions))
    }

    func restricted(
        order: RationalBezierDerivativeOrder,
        to interval: ScalarInterval
    ) -> RationalBezierRestrictedDerivativePolynomials? {
        let key = RationalBezierDerivativeRestrictionKey(
            order: order,
            lower: interval.lower,
            upper: interval.upper
        )
        if let cached = state.withLock({ $0.restrictions[key] }) {
            return cached
        }
        guard let root = roots[order] else { return nil }
        guard let parentInterval = dyadicParent(of: interval),
              let parent = restricted(order: order, to: parentInterval),
              let split = parent.splitAtMidpoint() else {
            return root.restricted(to: interval)
        }
        let middle = parentInterval.midpoint
        let leftKey = RationalBezierDerivativeRestrictionKey(
            order: order,
            lower: parentInterval.lower,
            upper: middle
        )
        let rightKey = RationalBezierDerivativeRestrictionKey(
            order: order,
            lower: middle,
            upper: parentInterval.upper
        )
        state.withLock { state in
            state.restrictions[leftKey] = split.left
            state.restrictions[rightKey] = split.right
        }
        return interval.upper == middle ? split.left : split.right
    }

    private func dyadicParent(
        of interval: ScalarInterval
    ) -> ScalarInterval? {
        let width = interval.width
        guard width.isFinite,
              width > 0.0,
              width < 1.0 else {
            return nil
        }
        let scaledIndex = interval.lower / width
        let roundedIndex = scaledIndex.rounded()
        guard roundedIndex.isFinite,
              abs(scaledIndex - roundedIndex) <= Double.ulpOfOne * 8.0,
              roundedIndex >= 0.0,
              roundedIndex <= Double(Int.max),
              let index = Int(exactly: roundedIndex) else {
            return nil
        }
        let parentLower: Double
        let parentUpper: Double
        if index.isMultiple(of: 2) {
            parentLower = interval.lower
            parentUpper = interval.upper + width
        } else {
            parentLower = interval.lower - width
            parentUpper = interval.upper
        }
        guard parentLower >= 0.0, parentUpper <= 1.0 else { return nil }
        do {
            return try ScalarInterval(lower: parentLower, upper: parentUpper)
        } catch {
            return nil
        }
    }
}

private struct BernsteinIntervalPolynomial: Sendable {
    let coefficients: [OutwardScalarInterval]
    let degree: Int

    init?(values: [Double]) {
        self.init(coefficients: values.map(OutwardScalarInterval.init))
    }

    init?(coefficients: [OutwardScalarInterval]) {
        guard coefficients.isEmpty == false,
              coefficients.allSatisfy(\.isFinite) else {
            return nil
        }
        self.coefficients = coefficients
        degree = coefficients.count - 1
    }

    func derivative(parameterWidth: Double) -> BernsteinIntervalPolynomial? {
        guard parameterWidth.isFinite, parameterWidth > 0.0 else { return nil }
        guard degree > 0 else {
            return BernsteinIntervalPolynomial(coefficients: [OutwardScalarInterval(0.0)])
        }
        guard let scale = OutwardScalarInterval(Double(degree)).divided(
            by: OutwardScalarInterval(parameterWidth)
        ) else {
            return nil
        }
        return BernsteinIntervalPolynomial(
            coefficients: (0..<degree).map { index in
                (coefficients[index + 1] - coefficients[index]) * scale
            }
        )
    }

    func subtracting(
        _ other: BernsteinIntervalPolynomial?
    ) -> BernsteinIntervalPolynomial? {
        guard let other, degree == other.degree else { return nil }
        return BernsteinIntervalPolynomial(
            coefficients: coefficients.indices.map { index in
                coefficients[index] - other.coefficients[index]
            }
        )
    }

    func scaled(by factor: Double) -> BernsteinIntervalPolynomial? {
        guard factor.isFinite else { return nil }
        let interval = OutwardScalarInterval(factor)
        return BernsteinIntervalPolynomial(
            coefficients: coefficients.map { $0 * interval }
        )
    }

    func multiplied(
        by other: BernsteinIntervalPolynomial
    ) -> BernsteinIntervalPolynomial? {
        let outputDegree = degree + other.degree
        guard let firstBinomial = Self.binomialRow(degree),
              let secondBinomial = Self.binomialRow(other.degree),
              let outputBinomial = Self.binomialRow(outputDegree) else {
            return nil
        }
        var result = Array(
            repeating: OutwardScalarInterval(0.0),
            count: outputDegree + 1
        )
        for outputIndex in 0...outputDegree {
            let firstLower = max(0, outputIndex - other.degree)
            let firstUpper = min(degree, outputIndex)
            var coefficient = OutwardScalarInterval(0.0)
            for firstIndex in firstLower...firstUpper {
                let secondIndex = outputIndex - firstIndex
                let numerator = firstBinomial[firstIndex]
                    * secondBinomial[secondIndex]
                guard let productWeight = numerator.divided(
                    by: outputBinomial[outputIndex]
                ) else {
                    return nil
                }
                coefficient = coefficient
                    + coefficients[firstIndex]
                    * other.coefficients[secondIndex]
                    * productWeight
            }
            result[outputIndex] = coefficient
        }
        return BernsteinIntervalPolynomial(coefficients: result)
    }

    var absoluteUpperBound: Double {
        coefficients.map(\.absoluteUpperBound).max()?.nextUp ?? .infinity
    }

    var minimumLowerBound: Double {
        coefficients.map(\.lower).min()?.nextDown ?? -.infinity
    }

    func restricted(to interval: ScalarInterval) -> BernsteinIntervalPolynomial? {
        guard interval.lower >= 0.0,
              interval.upper <= 1.0,
              interval.width > 0.0 else {
            return nil
        }
        if interval.lower == 0.0, interval.upper == 1.0 {
            return self
        }
        let upperRestricted: BernsteinIntervalPolynomial
        if interval.upper < 1.0 {
            guard let split = split(at: interval.upper) else { return nil }
            upperRestricted = split.left
        } else {
            upperRestricted = self
        }
        guard interval.lower > 0.0 else { return upperRestricted }
        let localLower = interval.lower / interval.upper
        guard let split = upperRestricted.split(at: localLower) else { return nil }
        return split.right
    }

    fileprivate func split(
        at parameter: Double
    ) -> (left: BernsteinIntervalPolynomial, right: BernsteinIntervalPolynomial)? {
        guard parameter.isFinite, parameter >= 0.0, parameter <= 1.0 else {
            return nil
        }
        let t = OutwardScalarInterval(parameter)
        let oneMinusT = OutwardScalarInterval(1.0 - parameter)
        var row = coefficients
        var left = [row[0]]
        var right = [row[degree]]
        if degree > 0 {
            for level in 1...degree {
                for index in 0...(degree - level) {
                    row[index] = row[index] * oneMinusT + row[index + 1] * t
                }
                left.append(row[0])
                right.append(row[degree - level])
            }
        }
        right.reverse()
        guard let leftPolynomial = BernsteinIntervalPolynomial(coefficients: left),
              let rightPolynomial = BernsteinIntervalPolynomial(coefficients: right) else {
            return nil
        }
        return (leftPolynomial, rightPolynomial)
    }

    private static func binomialRow(_ degree: Int) -> [OutwardScalarInterval]? {
        guard degree >= 0 else { return nil }
        var row = Array(repeating: Int64(0), count: degree + 1)
        row[0] = 1
        guard degree > 0 else { return [OutwardScalarInterval(1.0)] }
        for currentN in 1...degree {
            let upper = currentN
            for index in stride(from: upper, through: 1, by: -1) {
                let sum = row[index].addingReportingOverflow(row[index - 1])
                guard sum.overflow == false else { return nil }
                row[index] = sum.partialValue
            }
        }
        return row.map { OutwardScalarInterval(Double($0)) }
    }
}
