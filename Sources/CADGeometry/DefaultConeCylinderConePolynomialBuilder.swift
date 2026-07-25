struct DefaultConeCylinderConePolynomialBuilder:
    ConeCylinderConePolynomialBuilding
{
    func polynomial(
        context: ConeCylinderConeIntersectionContext
    ) -> ConeCylinderConePolynomial {
        let first = polynomialEquation(context.sourceEquation)
        let second = polynomialEquation(context.targetEquation)
        let firstMagnitude = polynomialEquationMagnitude(
            context.sourceEquation
        )
        let secondMagnitude = polynomialEquationMagnitude(
            context.targetEquation
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
        return ConeCylinderConePolynomial(
            coefficients: coefficients,
            forwardErrorScale: forwardErrorBounds.max() ?? 0.0
        )
    }

    private func polynomialEquation(
        _ equation: ConeCylinderConeIntersectionContext.HeightQuadratic
    ) -> (
        leading: [Double],
        linear: [Double],
        constant: [Double]
    ) {
        let denominator = [1.0, 0.0, 1.0]
        let denominatorSquared = [1.0, 0.0, 2.0, 0.0, 1.0]
        return (
            scaled(denominatorSquared, by: equation.leading),
            scaled(
                multiplied(
                    linearNumerator(equation.halfLinear),
                    denominator
                ),
                by: 2.0
            ),
            quadraticNumerator(equation.constant)
        )
    }

    private func polynomialEquationMagnitude(
        _ equation: ConeCylinderConeIntersectionContext.HeightQuadratic
    ) -> (
        leading: [Double],
        linear: [Double],
        constant: [Double]
    ) {
        let denominator = [1.0, 0.0, 1.0]
        let denominatorSquared = [1.0, 0.0, 2.0, 0.0, 1.0]
        return (
            scaled(denominatorSquared, by: abs(equation.leading)),
            scaled(
                multiplied(
                    linearNumeratorMagnitude(equation.halfLinear),
                    denominator
                ),
                by: 2.0
            ),
            quadraticNumeratorMagnitude(equation.constant)
        )
    }

    private func linearNumerator(
        _ polynomial:
            ConeCylinderConeIntersectionContext.TrigonometricQuadratic
    ) -> [Double] {
        [
            polynomial.constant + polynomial.cosine,
            2.0 * polynomial.sine,
            polynomial.constant - polynomial.cosine,
        ]
    }

    private func linearNumeratorMagnitude(
        _ polynomial:
            ConeCylinderConeIntersectionContext.TrigonometricQuadratic
    ) -> [Double] {
        [
            abs(polynomial.constant) + abs(polynomial.cosine),
            2.0 * abs(polynomial.sine),
            abs(polynomial.constant) + abs(polynomial.cosine),
        ]
    }

    private func quadraticNumerator(
        _ polynomial:
            ConeCylinderConeIntersectionContext.TrigonometricQuadratic
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
        _ polynomial:
            ConeCylinderConeIntersectionContext.TrigonometricQuadratic
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
