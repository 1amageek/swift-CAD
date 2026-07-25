struct DefaultHeightQuadraticResultantPolynomialBuilder:
    HeightQuadraticResultantPolynomialBuilding
{
    func polynomial(
        first firstEquation: TrigonometricHeightQuadratic,
        second secondEquation: TrigonometricHeightQuadratic
    ) -> HeightQuadraticResultantPolynomial {
        let first = polynomialEquation(firstEquation)
        let second = polynomialEquation(secondEquation)
        let firstMagnitude = polynomialEquationMagnitude(
            firstEquation
        )
        let secondMagnitude = polynomialEquationMagnitude(
            secondEquation
        )
        let leadingConstant = subtracted(
            multiplied(first.leading, second.constant),
            multiplied(first.constant, second.leading)
        )
        let leadingLinear = subtracted(
            multiplied(first.leading, second.linear),
            multiplied(first.linear, second.leading)
        )
        let linearConstant = subtracted(
            multiplied(first.linear, second.constant),
            multiplied(first.constant, second.linear)
        )
        let leadingConstantMagnitude = added(
            multiplied(firstMagnitude.leading, secondMagnitude.constant),
            multiplied(firstMagnitude.constant, secondMagnitude.leading)
        )
        let leadingLinearMagnitude = added(
            multiplied(firstMagnitude.leading, secondMagnitude.linear),
            multiplied(firstMagnitude.linear, secondMagnitude.leading)
        )
        let linearConstantMagnitude = added(
            multiplied(firstMagnitude.linear, secondMagnitude.constant),
            multiplied(firstMagnitude.constant, secondMagnitude.linear)
        )
        let coefficients = subtracted(
            multiplied(leadingConstant, leadingConstant),
            multiplied(leadingLinear, linearConstant)
        )
        let forwardErrorBounds = added(
            multiplied(
                leadingConstantMagnitude,
                leadingConstantMagnitude
            ),
            multiplied(
                leadingLinearMagnitude,
                linearConstantMagnitude
            )
        )
        return HeightQuadraticResultantPolynomial(
            coefficients: coefficients,
            forwardErrorScale: forwardErrorBounds.max() ?? 0.0
        )
    }

    private func polynomialEquation(
        _ equation: TrigonometricHeightQuadratic
    ) -> (
        leading: [Double],
        linear: [Double],
        constant: [Double]
    ) {
        return (
            quadraticNumerator(equation.leading),
            scaled(quadraticNumerator(equation.halfLinear), by: 2.0),
            quadraticNumerator(equation.constant)
        )
    }

    private func polynomialEquationMagnitude(
        _ equation: TrigonometricHeightQuadratic
    ) -> (
        leading: [Double],
        linear: [Double],
        constant: [Double]
    ) {
        return (
            quadraticNumeratorMagnitude(equation.leading),
            scaled(
                quadraticNumeratorMagnitude(equation.halfLinear),
                by: 2.0
            ),
            quadraticNumeratorMagnitude(equation.constant)
        )
    }

    private func quadraticNumerator(
        _ polynomial: SecondOrderTrigonometricPolynomial
    ) -> [Double] {
        [
            polynomial.constant
                + polynomial.cosine
                + polynomial.cosineDouble,
            2.0 * polynomial.sine
                + 4.0 * polynomial.sineDouble,
            2.0 * polynomial.constant
                - 6.0 * polynomial.cosineDouble,
            2.0 * polynomial.sine
                - 4.0 * polynomial.sineDouble,
            polynomial.constant
                - polynomial.cosine
                + polynomial.cosineDouble,
        ]
    }

    private func quadraticNumeratorMagnitude(
        _ polynomial: SecondOrderTrigonometricPolynomial
    ) -> [Double] {
        [
            abs(polynomial.constant)
                + abs(polynomial.cosine)
                + abs(polynomial.cosineDouble),
            2.0 * abs(polynomial.sine)
                + 4.0 * abs(polynomial.sineDouble),
            2.0 * abs(polynomial.constant)
                + 6.0 * abs(polynomial.cosineDouble),
            2.0 * abs(polynomial.sine)
                + 4.0 * abs(polynomial.sineDouble),
            abs(polynomial.constant)
                + abs(polynomial.cosine)
                + abs(polynomial.cosineDouble),
        ]
    }

    private func added(
        _ first: [Double],
        _ second: [Double]
    ) -> [Double] {
        let count = max(first.count, second.count)
        var result = Array(repeating: 0.0, count: count)
        for index in first.indices {
            result[index] += first[index]
        }
        for index in second.indices {
            result[index] += second[index]
        }
        return result
    }

    private func subtracted(
        _ first: [Double],
        _ second: [Double]
    ) -> [Double] {
        added(first, scaled(second, by: -1.0))
    }

    private func scaled(
        _ polynomial: [Double],
        by scalar: Double
    ) -> [Double] {
        polynomial.map { $0 * scalar }
    }

    private func multiplied(
        _ first: [Double],
        _ second: [Double]
    ) -> [Double] {
        var result = Array(
            repeating: 0.0,
            count: first.count + second.count - 1
        )
        for firstIndex in first.indices {
            for secondIndex in second.indices {
                result[firstIndex + secondIndex] +=
                    first[firstIndex] * second[secondIndex]
            }
        }
        return result
    }
}
