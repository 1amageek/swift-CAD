import Foundation

enum RationalBSplineSupport {
    static func basis(
        index: Int,
        degree: Int,
        parameter: Double,
        knots: [Double],
        derivative: Int = 0
    ) -> Double {
        guard index >= 0, degree >= 0, derivative >= 0 else {
            return 0.0
        }
        if derivative == 0 {
            return basisValue(index: index, degree: degree, parameter: parameter, knots: knots)
        }
        guard degree > 0 else {
            return 0.0
        }
        let leftDenominator = knots[index + degree] - knots[index]
        let rightDenominator = knots[index + degree + 1] - knots[index + 1]
        let left = leftDenominator > 0.0
            ? Double(degree) / leftDenominator
                * basis(index: index, degree: degree - 1, parameter: parameter, knots: knots, derivative: derivative - 1)
            : 0.0
        let right = rightDenominator > 0.0
            ? Double(degree) / rightDenominator
                * basis(index: index + 1, degree: degree - 1, parameter: parameter, knots: knots, derivative: derivative - 1)
            : 0.0
        return left - right
    }

    private static func basisValue(
        index: Int,
        degree: Int,
        parameter: Double,
        knots: [Double]
    ) -> Double {
        guard index >= 0, index + degree + 1 < knots.count else {
            return 0.0
        }
        if degree == 0 {
            let isInSpan = parameter >= knots[index] && parameter < knots[index + 1]
            let isLastEndpoint = parameter == knots[knots.count - 1]
                && index + 1 == knots.count - 1
            return isInSpan || isLastEndpoint ? 1.0 : 0.0
        }
        let leftDenominator = knots[index + degree] - knots[index]
        let rightDenominator = knots[index + degree + 1] - knots[index + 1]
        let left = leftDenominator > 0.0
            ? (parameter - knots[index]) / leftDenominator
                * basisValue(index: index, degree: degree - 1, parameter: parameter, knots: knots)
            : 0.0
        let right = rightDenominator > 0.0
            ? (knots[index + degree + 1] - parameter) / rightDenominator
                * basisValue(index: index + 1, degree: degree - 1, parameter: parameter, knots: knots)
            : 0.0
        return left + right
    }
}
