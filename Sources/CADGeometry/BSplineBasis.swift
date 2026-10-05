import CADCore
import Foundation

public struct BSplineBasis {
    struct NonzeroIntervalValues: Sendable {
        let startIndex: Int
        let values: [OutwardScalarInterval]
    }

    static func nonzeroIntervalDerivativeValues(parameter: Double, degree: Int,
        throughDerivativeOrder order: Int, knots: [Double], count: Int,
        owningSpan: Int, tolerance: ModelingTolerance) throws -> [NonzeroIntervalValues] {
        try validateSelectedSpan(parameter: parameter, degree: degree, order: order,
            knots: knots, count: count, span: owningSpan, tolerance: tolerance)
        typealias Interval = OutwardScalarInterval
        var previous = Array(repeating: [Interval.exact(0)], count: order + 1)
        previous[0][0] = .exact(1)
        if degree > 0 {
            for p in 1...degree {
                try Task.checkCancellation()
                let start = owningSpan - p
                var next = Array(repeating: Array(repeating: Interval.exact(0), count: p + 1), count: order + 1)
                func value(_ derivative: Int, _ index: Int) -> Interval {
                    guard index > start, index <= owningSpan else { return .exact(0) }
                    return previous[derivative][index - start - 1]
                }
                for offset in 0...p {
                    let i = start + offset
                    let left = Interval.exact(knots[i + p]) - .exact(knots[i])
                    let right = Interval.exact(knots[i + p + 1]) - .exact(knots[i + 1])
                    if knots[i + p] > knots[i] {
                        guard let factor = (Interval.exact(parameter) - .exact(knots[i])).divided(by: left),
                              let scale = Interval.exact(Double(p)).divided(by: left) else {
                            throw selectedFailure(.resourceLimitExceeded, "Original left knot difference has no finite positive enclosure.", tolerance)
                        }
                        next[0][offset] = next[0][offset] + factor * value(0, i)
                        for derivative in 1...max(1, min(p, order)) where derivative <= order {
                            next[derivative][offset] = next[derivative][offset] + scale * value(derivative - 1, i)
                        }
                    }
                    if knots[i + p + 1] > knots[i + 1] {
                        guard let factor = (Interval.exact(knots[i + p + 1]) - .exact(parameter)).divided(by: right),
                              let scale = Interval.exact(Double(p)).divided(by: right) else {
                            throw selectedFailure(.resourceLimitExceeded, "Original right knot difference has no finite positive enclosure.", tolerance)
                        }
                        next[0][offset] = next[0][offset] + factor * value(0, i + 1)
                        for derivative in 1...max(1, min(p, order)) where derivative <= order {
                            next[derivative][offset] = next[derivative][offset] - scale * value(derivative - 1, i + 1)
                        }
                    }
                }
                previous = next
            }
        }
        guard previous.joined().allSatisfy(\.isFinite) else {
            throw selectedFailure(.resourceLimitExceeded, "Original interval basis derivatives exceed finite arithmetic.", tolerance)
        }
        return previous.map { NonzeroIntervalValues(startIndex: owningSpan - degree, values: $0) }
    }

    private static func validateSelectedSpan(parameter: Double, degree: Int, order: Int,
        knots: [Double], count: Int, span: Int, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try Task.checkCancellation()
        let sum = count.addingReportingOverflow(degree)
        let length = sum.partialValue.addingReportingOverflow(1)
        let rows = order.addingReportingOverflow(1)
        let columns = degree.addingReportingOverflow(1)
        let cells = rows.partialValue.multipliedReportingOverflow(by: columns.partialValue)
        guard !sum.overflow, !length.overflow, !rows.overflow, !columns.overflow, !cells.overflow else {
            throw selectedFailure(.resourceLimitExceeded, "Selected original basis storage count overflowed.", tolerance)
        }
        guard degree >= 0, count > degree, order >= 0, knots.count == length.partialValue,
              span >= degree, span < count, parameter.isFinite,
              knots.allSatisfy(\.isFinite), zip(knots, knots.dropFirst()).allSatisfy({ $0.0 <= $0.1 }),
              knots[span] < knots[span + 1], parameter >= knots[span], parameter <= knots[span + 1] else {
            throw selectedFailure(.invalidInput, "A selected original basis requires its actual finite closed native span.", tolerance)
        }
    }

    private static func selectedFailure(_ code: KernelErrorCode, _ message: String,
                                        _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }

    public struct NonzeroValues: Sendable, Hashable {
        public let startIndex: Int
        public let values: [Double]

        public init(startIndex: Int, values: [Double]) {
            self.startIndex = startIndex
            self.values = values
        }
    }

    public static func values(parameter: Double, degree: Int, knots: [Double], count: Int) -> [Double] {
        var values = Array(repeating: 0.0, count: count)
        let upperDomain = knots[knots.count - degree - 1]
        for index in 0..<count {
            if parameter == upperDomain {
                if index == upperEndpointBasisIndex(upperDomain: upperDomain, knots: knots, count: count) {
                    values[index] = 1.0
                }
            } else if parameter >= knots[index] && parameter < knots[index + 1] {
                values[index] = 1.0
            }
        }
        guard degree > 0 else {
            return values
        }
        for currentDegree in 1...degree {
            var next = Array(repeating: 0.0, count: count)
            for index in 0..<count {
                let leftDenominator = knots[index + currentDegree] - knots[index]
                let rightDenominator = knots[index + currentDegree + 1] - knots[index + 1]
                let left = leftDenominator > 0.0
                    ? ((parameter - knots[index]) / leftDenominator) * values[index]
                    : 0.0
                let right = (index + 1 < count && rightDenominator > 0.0)
                    ? ((knots[index + currentDegree + 1] - parameter) / rightDenominator) * values[index + 1]
                    : 0.0
                next[index] = left + right
            }
            values = next
        }
        return values
    }

    public static func derivativeValues(
        parameter: Double,
        degree: Int,
        derivativeOrder: Int,
        knots: [Double],
        count: Int
    ) -> [Double] {
        guard derivativeOrder > 0 else {
            return values(parameter: parameter, degree: degree, knots: knots, count: count)
        }
        guard degree > 0, derivativeOrder <= degree else {
            return Array(repeating: 0.0, count: count)
        }
        let lowerDerivative = derivativeValues(
            parameter: parameter,
            degree: degree - 1,
            derivativeOrder: derivativeOrder - 1,
            knots: knots,
            count: count + 1
        )
        var values = Array(repeating: 0.0, count: count)
        for index in 0..<count {
            let leftDenominator = knots[index + degree] - knots[index]
            let rightDenominator = knots[index + degree + 1] - knots[index + 1]
            let left = leftDenominator > 0.0
                ? Double(degree) * lowerDerivative[index] / leftDenominator
                : 0.0
            let right = rightDenominator > 0.0
                ? Double(degree) * lowerDerivative[index + 1] / rightDenominator
                : 0.0
            values[index] = left - right
        }
        return values
    }

    public static func nonzeroValues(
        parameter: Double,
        degree: Int,
        derivativeOrder: Int = 0,
        knots: [Double],
        count: Int
    ) -> NonzeroValues {
        nonzeroDerivativeValues(
            parameter: parameter,
            degree: degree,
            throughDerivativeOrder: derivativeOrder,
            knots: knots,
            count: count
        )[max(derivativeOrder, 0)]
    }

    static func nonzeroDerivativeValues(
        parameter: Double,
        degree: Int,
        throughDerivativeOrder derivativeOrder: Int,
        knots: [Double],
        count: Int
    ) -> [NonzeroValues] {
        let requestedOrder = max(derivativeOrder, 0)
        let evaluatedOrder = min(requestedOrder, degree)
        let clamped = clampedParameter(parameter, knots: knots, degree: degree)
        if degree == 2, count == 3, knots.count == 6, requestedOrder <= 2,
           knots[0] == knots[2], knots[3] == knots[5] {
            let width = knots[3] - knots[2]
            if width.isFinite, width > 0 {
                let t = (clamped - knots[2]) / width
                let s = 1 - t
                return (0...requestedOrder).map { order in
                    let values: [Double]
                    switch order {
                    case 0: values = [s * s, 2 * s * t, t * t]
                    case 1: values = [-2 * s / width, 2 * (s - t) / width, 2 * t / width]
                    default:
                        let scale = 2 / width / width
                        values = [scale, -2 * scale, scale]
                    }
                    return NonzeroValues(startIndex: 0, values: values)
                }
            }
        }
        let span = knotSpan(
            parameter: clamped,
            degree: degree,
            knots: knots,
            count: count
        )
        let derivatives = localDerivatives(
            parameter: clamped,
            span: span,
            degree: degree,
            derivativeOrder: evaluatedOrder,
            knots: knots
        )
        return (0...requestedOrder).map { order in
            NonzeroValues(
                startIndex: span - degree,
                values: order <= degree
                    ? derivatives[order]
                    : Array(repeating: 0.0, count: degree + 1)
            )
        }
    }

    public static func clampedParameter(_ parameter: Double, knots: [Double], degree: Int) -> Double {
        let lowerBound = knots[degree]
        let upperBound = knots[knots.count - degree - 1]
        return min(max(parameter, lowerBound), upperBound)
    }

    private static func upperEndpointBasisIndex(upperDomain: Double, knots: [Double], count: Int) -> Int {
        for index in stride(from: count - 1, through: 0, by: -1) {
            guard index + 1 < knots.count else {
                continue
            }
            if knots[index] < upperDomain && knots[index + 1] == upperDomain {
                return index
            }
        }
        return max(count - 1, 0)
    }

    private static func knotSpan(
        parameter: Double,
        degree: Int,
        knots: [Double],
        count: Int
    ) -> Int {
        let lastIndex = count - 1
        if parameter >= knots[count] {
            return lastIndex
        }
        var lower = degree
        var upper = count
        var middle = (lower + upper) / 2
        while parameter < knots[middle] || parameter >= knots[middle + 1] {
            if parameter < knots[middle] {
                upper = middle
            } else {
                lower = middle
            }
            middle = (lower + upper) / 2
        }
        return middle
    }

    private static func localDerivatives(
        parameter: Double,
        span: Int,
        degree: Int,
        derivativeOrder: Int,
        knots: [Double]
    ) -> [[Double]] {
        var basis = Array(
            repeating: Array(repeating: 0.0, count: degree + 1),
            count: degree + 1
        )
        var left = Array(repeating: 0.0, count: degree + 1)
        var right = Array(repeating: 0.0, count: degree + 1)
        basis[0][0] = 1.0
        if degree > 0 {
            for column in 1...degree {
                left[column] = parameter - knots[span + 1 - column]
                right[column] = knots[span + column] - parameter
                var saved = 0.0
                for row in 0..<column {
                    let denominator = right[row + 1] + left[column - row]
                    basis[column][row] = denominator
                    let temporary = denominator != 0.0
                        ? basis[row][column - 1] / denominator
                        : 0.0
                    basis[row][column] = saved + right[row + 1] * temporary
                    saved = left[column - row] * temporary
                }
                basis[column][column] = saved
            }
        }

        var derivatives = Array(
            repeating: Array(repeating: 0.0, count: degree + 1),
            count: derivativeOrder + 1
        )
        for index in 0...degree {
            derivatives[0][index] = basis[index][degree]
        }
        guard derivativeOrder > 0 else { return derivatives }

        var workspace = Array(
            repeating: Array(repeating: 0.0, count: degree + 1),
            count: 2
        )
        for basisIndex in 0...degree {
            var firstRow = 0
            var secondRow = 1
            workspace[firstRow][0] = 1.0
            for order in 1...derivativeOrder {
                var derivative = 0.0
                let reducedIndex = basisIndex - order
                let reducedDegree = degree - order
                if basisIndex >= order {
                    let denominator = basis[reducedDegree + 1][reducedIndex]
                    workspace[secondRow][0] = denominator != 0.0
                        ? workspace[firstRow][0] / denominator
                        : 0.0
                    derivative = workspace[secondRow][0]
                        * basis[reducedIndex][reducedDegree]
                }
                let lower = reducedIndex >= -1 ? 1 : -reducedIndex
                let upper = basisIndex - 1 <= reducedDegree
                    ? order - 1
                    : degree - basisIndex
                if lower <= upper {
                    for index in lower...upper {
                        let denominator = basis[reducedDegree + 1][reducedIndex + index]
                        workspace[secondRow][index] = denominator != 0.0
                            ? (workspace[firstRow][index]
                                - workspace[firstRow][index - 1]) / denominator
                            : 0.0
                        derivative += workspace[secondRow][index]
                            * basis[reducedIndex + index][reducedDegree]
                    }
                }
                if basisIndex <= reducedDegree {
                    let denominator = basis[reducedDegree + 1][basisIndex]
                    workspace[secondRow][order] = denominator != 0.0
                        ? -workspace[firstRow][order - 1] / denominator
                        : 0.0
                    derivative += workspace[secondRow][order]
                        * basis[basisIndex][reducedDegree]
                }
                derivatives[order][basisIndex] = derivative
                swap(&firstRow, &secondRow)
                workspace[secondRow] = Array(repeating: 0.0, count: degree + 1)
            }
        }

        var multiplier = Double(degree)
        if derivativeOrder > 0 {
            for order in 1...derivativeOrder {
                for index in 0...degree {
                    derivatives[order][index] *= multiplier
                }
                multiplier *= Double(degree - order)
            }
        }
        return derivatives
    }
}
