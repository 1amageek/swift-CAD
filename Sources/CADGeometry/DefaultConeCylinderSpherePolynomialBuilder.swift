struct DefaultConeCylinderSpherePolynomialBuilder:
    ConeCylinderSpherePolynomialBuilding
{
    func polynomial(
        context: ConeCylinderSphereIntersectionContext
    ) -> ConeCylinderSpherePolynomial {
        // The source cone and target sphere are both quadratic in cylinder
        // height. Their resultant is
        // C² - 2 M C A + N A², where A = 2(L - Q M) and C = B - Q N.
        // Tangent-half-angle substitution gives degree at most eight.
        let coneHalfLinear = linearNumerator(context.coneHalfLinear)
        let coneBaseQuadratic = quadraticNumerator(
            context.coneBaseQuadratic
        )
        let sphereHalfLinear = linearNumerator(
            context.sphereHalfLinear
        )
        let sphereBaseQuadratic = quadraticNumerator(
            context.sphereBaseQuadratic
        )
        let coneHalfLinearMagnitude = linearNumeratorMagnitude(
            context.coneHalfLinear
        )
        let coneBaseQuadraticMagnitude = quadraticNumeratorMagnitude(
            context.coneBaseQuadratic
        )
        let sphereHalfLinearMagnitude = linearNumeratorMagnitude(
            context.sphereHalfLinear
        )
        let sphereBaseQuadraticMagnitude = quadraticNumeratorMagnitude(
            context.sphereBaseQuadratic
        )
        let heightLinear = scaled(
            subtracted(
                coneHalfLinear,
                scaled(
                    sphereHalfLinear,
                    by: context.generatorQuadratic
                )
            ),
            by: 2.0
        )
        let constant = subtracted(
            coneBaseQuadratic,
            scaled(
                sphereBaseQuadratic,
                by: context.generatorQuadratic
            )
        )
        let generatorMagnitude = abs(context.generatorQuadratic)
        let heightLinearMagnitude = scaled(
            added(
                coneHalfLinearMagnitude,
                scaled(
                    sphereHalfLinearMagnitude,
                    by: generatorMagnitude
                )
            ),
            by: 2.0
        )
        let constantMagnitude = added(
            coneBaseQuadraticMagnitude,
            scaled(
                sphereBaseQuadraticMagnitude,
                by: generatorMagnitude
            )
        )
        let squaredConstant = multiplied(constant, constant)
        let mixedTerm = scaled(
            multiplied(
                multiplied(sphereHalfLinear, constant),
                heightLinear
            ),
            by: 2.0
        )
        let squaredHeight = multiplied(
            sphereBaseQuadratic,
            multiplied(heightLinear, heightLinear)
        )
        let coefficients = added(
            subtracted(
                squaredConstant,
                mixedTerm
            ),
            squaredHeight
        )
        let forwardErrorBounds = added(
            added(
                multiplied(
                    constantMagnitude,
                    constantMagnitude
                ),
                scaled(
                    multiplied(
                        multiplied(
                            sphereHalfLinearMagnitude,
                            constantMagnitude
                        ),
                        heightLinearMagnitude
                    ),
                    by: 2.0
                )
            ),
            multiplied(
                sphereBaseQuadraticMagnitude,
                multiplied(
                    heightLinearMagnitude,
                    heightLinearMagnitude
                )
            )
        )
        return ConeCylinderSpherePolynomial(
            coefficients: coefficients,
            forwardErrorScale: forwardErrorBounds.max() ?? 0.0
        )
    }

    private func linearNumerator(
        _ polynomial:
            ConeCylinderSphereIntersectionContext.TrigonometricQuadratic
    ) -> [Double] {
        [
            polynomial.constant + polynomial.cosine,
            2.0 * polynomial.sine,
            polynomial.constant - polynomial.cosine,
        ]
    }

    private func linearNumeratorMagnitude(
        _ polynomial:
            ConeCylinderSphereIntersectionContext.TrigonometricQuadratic
    ) -> [Double] {
        [
            abs(polynomial.constant) + abs(polynomial.cosine),
            2.0 * abs(polynomial.sine),
            abs(polynomial.constant) + abs(polynomial.cosine),
        ]
    }

    private func quadraticNumerator(
        _ polynomial:
            ConeCylinderSphereIntersectionContext.TrigonometricQuadratic
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
            ConeCylinderSphereIntersectionContext.TrigonometricQuadratic
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
