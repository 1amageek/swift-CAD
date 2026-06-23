import Foundation

struct BSplineBasis {
    static func values(parameter: Double, degree: Int, knots: [Double], count: Int) -> [Double] {
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

    static func derivativeValues(
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

    static func clampedParameter(_ parameter: Double, knots: [Double], degree: Int) -> Double {
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
}
