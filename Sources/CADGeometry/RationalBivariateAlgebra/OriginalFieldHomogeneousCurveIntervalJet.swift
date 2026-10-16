/// Exact-domain jets of original XYZ/W after an ordered-field placement action.
package struct OriginalFieldHomogeneousCurveIntervalJet: Sendable {
    package let homogeneous: [OriginalSingularFieldPlanePolynomial]
    package let lowerParameter: ExactRationalCoefficient
    package let upperParameter: ExactRationalCoefficient
    package let maximumAlgebraicDepth: Int
    package let jet: IntervalVectorDerivativeJet

    package init<B: ExactScalarAdmission & ~Copyable>(homogeneous: [OriginalSingularFieldPlanePolynomial],
        lowerParameter: ExactRationalCoefficient, upperParameter: ExactRationalCoefficient,
        throughOrder: Int, maximumCoefficientWidth: ExactRationalCoefficient,
        maximumAlgebraicDepth: Int, usage: inout B) throws {
        guard homogeneous.count == 4, let first = homogeneous.first,
              !homogeneous[3].isZero, (0...3).contains(throughOrder),
              maximumAlgebraicDepth >= 0, maximumCoefficientWidth.isPositive,
              first.context.coefficientDepth <= maximumAlgebraicDepth,
              !(try upperParameter.subtracting(lowerParameter, usage: &usage)).isNegative else {
            throw rationalAlgebraFailure("Original field curve jet needs full XYZ/W, exact bounds and independent coefficient precision.")
        }
        let result = try usage.withProofScope(maximum: .init(value: Int.max, coefficient: maximumAlgebraicDepth)) { usage in
            let context = first.context, depth = maximumAlgebraicDepth
            for value in homogeneous {
                try usage.consumeWork(1)
                guard value.context === context, value.vDegree <= 0 else {
                    throw rationalAlgebraFailure("Original field curve coordinates have unrelated owners or a second parameter.")
                }
            }
            let count = try rationalAlgebraCount(throughOrder, 1)
            try RationalAlgebraStorage.retain(try rationalAlgebraCount(count, 3, multiply: true),
                of: OutwardScalarInterval.self, usage: &usage)
            try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldPlanePolynomial.self, usage: &usage)
            var row = Array(homogeneous[0..<3])
            let weight = homogeneous[3]
            let weightDerivative = try weight.differentiated(alongU: true, maximumDepth: depth, usage: &usage)
            var denominator = weight
            var x: [OutwardScalarInterval] = [], y: [OutwardScalarInterval] = [], z: [OutwardScalarInterval] = []
            x.reserveCapacity(count); y.reserveCapacity(count); z.reserveCapacity(count)
            for order in 0...throughOrder {
                try usage.consumeWork(1)
                let divisor = try OriginalFieldPolynomialRange(original: denominator,
                    lower: lowerParameter, upper: upperParameter, maximumDepth: depth, usage: &usage)
                for axis in 0..<3 {
                    let numerator = try OriginalFieldPolynomialRange(original: row[axis],
                        lower: lowerParameter, upper: upperParameter, maximumDepth: depth, usage: &usage)
                    let value = try numerator.divided(by: divisor, maximumDepth: depth, usage: &usage)
                        .outward(maximumCoefficientWidth: maximumCoefficientWidth, maximumDepth: depth, usage: &usage)
                    switch axis { case 0: x.append(value); case 1: y.append(value); default: z.append(value) }
                }
                if order < throughOrder {
                    let scale = try OriginalSingularFieldElement.constant(.natural(order + 1, usage: &usage),
                        in: context, maximumDepth: depth, usage: &usage)
                    let scaledWeightDerivative = try weightDerivative.multiplied(by:
                        .constant(scale, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
                    try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldPlanePolynomial.self, usage: &usage)
                    var next: [OriginalSingularFieldPlanePolynomial] = []; next.reserveCapacity(3)
                    for numerator in row {
                        next.append(try numerator.differentiated(alongU: true, maximumDepth: depth, usage: &usage)
                            .multiplied(by: weight, maximumDepth: depth, usage: &usage)
                            .subtracting(numerator.multiplied(by: scaledWeightDerivative,
                                maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage))
                    }
                    row = next
                    denominator = try denominator.multiplied(by: weight, maximumDepth: depth, usage: &usage)
                }
            }
            return IntervalVectorDerivativeJet(x: .init(derivatives: x), y: .init(derivatives: y), z: .init(derivatives: z))
        }
        self.homogeneous = homogeneous; self.lowerParameter = lowerParameter; self.upperParameter = upperParameter
        self.maximumAlgebraicDepth = maximumAlgebraicDepth; jet = result
    }
}
