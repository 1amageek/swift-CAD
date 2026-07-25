import CADCore

struct DefaultParallelTorusTorusPlanePolynomialBuilder:
    ParallelTorusTorusPlanePolynomialBuilding
{
    func coefficients(
        context: ParallelTorusTorusPlaneIntersectionContext,
        planeOrigin: Point3D,
        planeNormal: Vector3D
    ) -> [Double] {
        // In the common-axis frame, the radial coordinate has the form
        // x = x0(theta) + k * q(theta), while y^2 = rho(theta)^2 - x^2
        // and q^2 is quadratic in sin(theta) and cos(theta). Eliminating y,
        // then q, and substituting t = tan(theta / 2) yields degree at most 8.
        let primaryMajor = context.primaryMajorRadius
        let primaryMinor = context.primaryMinorRadius
        let secondaryMajor = context.secondaryMajorRadius
        let secondaryMinor = context.secondaryMinorRadius
        let radialOffset = context.radialOffset
        let axialOffset = context.axialOffset
        let axialCoefficient = planeNormal.dot(context.primaryAxis)
        let radialCoefficient = planeNormal.dot(context.radialDirection)
        let quarterCoefficient = planeNormal.dot(context.quarterDirection)
        let planeConstant = (context.primaryCenter - planeOrigin).dot(
            planeNormal
        )

        let denominator = [1.0, 0.0, 1.0]
        let denominatorSquared = multiplied(denominator, denominator)
        let axialNumerator = added(
            scaled(denominator, by: axialOffset),
            [0.0, 2.0 * primaryMinor]
        )
        let secondaryTubeSquaredNumerator = subtracted(
            scaled(
                denominatorSquared,
                by: secondaryMinor * secondaryMinor
            ),
            multiplied(axialNumerator, axialNumerator)
        )
        let primaryRadiusNumerator = [
            primaryMajor + primaryMinor,
            0.0,
            primaryMajor - primaryMinor,
        ]
        let radialConstant = (
            primaryMajor * primaryMajor
                + primaryMinor * primaryMinor
                + radialOffset * radialOffset
                - secondaryMajor * secondaryMajor
                - secondaryMinor * secondaryMinor
                + axialOffset * axialOffset
        ) / (2.0 * radialOffset)
        let radialCosine = primaryMajor * primaryMinor / radialOffset
        let radialSine = axialOffset * primaryMinor / radialOffset
        let radialNumerator = linearTrigonometricNumerator(
            constant: radialConstant,
            cosine: radialCosine,
            sine: radialSine
        )
        let radicalCoefficient = -context.secondaryRadialSign
            * secondaryMajor / radialOffset
        let planeLinearNumerator = linearTrigonometricNumerator(
            constant: planeConstant
                + radialCoefficient * radialConstant,
            cosine: radialCoefficient * radialCosine,
            sine: axialCoefficient * primaryMinor
                + radialCoefficient * radialSine
        )
        let planeRadicalCoefficient = radialCoefficient
            * radicalCoefficient
        let quarterSquared = quarterCoefficient * quarterCoefficient
        let radicalSquaredFactor = planeRadicalCoefficient
                * planeRadicalCoefficient
            + quarterSquared * radicalCoefficient * radicalCoefficient
        let base = added(
            subtracted(
                multiplied(
                    planeLinearNumerator,
                    planeLinearNumerator
                ),
                scaled(
                    multiplied(
                        primaryRadiusNumerator,
                        primaryRadiusNumerator
                    ),
                    by: quarterSquared
                )
            ),
            added(
                scaled(
                    multiplied(radialNumerator, radialNumerator),
                    by: quarterSquared
                ),
                scaled(
                    secondaryTubeSquaredNumerator,
                    by: radicalSquaredFactor
                )
            )
        )
        let radical = scaled(
            added(
                scaled(
                    planeLinearNumerator,
                    by: planeRadicalCoefficient
                ),
                scaled(
                    radialNumerator,
                    by: quarterSquared * radicalCoefficient
                )
            ),
            by: 2.0
        )
        return subtracted(
            multiplied(base, base),
            multiplied(
                multiplied(radical, radical),
                secondaryTubeSquaredNumerator
            )
        )
    }

    private func linearTrigonometricNumerator(
        constant: Double,
        cosine: Double,
        sine: Double
    ) -> [Double] {
        [
            constant + cosine,
            2.0 * sine,
            constant - cosine,
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
