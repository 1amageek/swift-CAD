import Foundation

public struct BSplineBasis {
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
