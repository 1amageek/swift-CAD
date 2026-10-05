/// Exact-domain jets of original XYZ/W after an ordered-field placement action.
package struct OriginalFieldHomogeneousCurveIntervalJet: Sendable {
    package let homogeneous: [OriginalSingularFieldPlanePolynomial]
    package let lowerParameter: ExactRationalCoefficient
    package let upperParameter: ExactRationalCoefficient
    package let maximumAlgebraicDepth: Int
    package let jet: IntervalVectorDerivativeJet

    package init<B: RationalAlgebraAdmitting>(homogeneous: [OriginalSingularFieldPlanePolynomial],
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
        var admission = RationalCoefficientDepthAdmission(base: usage, maximumDepth: maximumAlgebraicDepth)
        defer { usage = admission.base }
        let context = first.context, depth = maximumAlgebraicDepth
        for value in homogeneous {
            try admission.consumeExactWork(1)
            guard value.context === context, value.vDegree <= 0 else {
                throw rationalAlgebraFailure("Original field curve coordinates have unrelated owners or a second parameter.")
            }
        }
        let count = try rationalAlgebraCount(throughOrder, 1)
        try RationalAlgebraStorage.retain(try rationalAlgebraCount(count, 3, multiply: true),
            of: OutwardScalarInterval.self, usage: &admission)
        try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldPlanePolynomial.self, usage: &admission)
        var row = Array(homogeneous[0..<3])
        let weight = homogeneous[3]
        let weightDerivative = try weight.differentiated(alongU: true, maximumDepth: depth, usage: &admission)
        var denominator = weight
        var x: [OutwardScalarInterval] = [], y: [OutwardScalarInterval] = [], z: [OutwardScalarInterval] = []
        x.reserveCapacity(count); y.reserveCapacity(count); z.reserveCapacity(count)
        for order in 0...throughOrder {
            try admission.consumeExactWork(1)
            let divisor = try OriginalFieldPolynomialRange(original: denominator,
                lower: lowerParameter, upper: upperParameter, maximumDepth: depth, usage: &admission)
            for axis in 0..<3 {
                let numerator = try OriginalFieldPolynomialRange(original: row[axis],
                    lower: lowerParameter, upper: upperParameter, maximumDepth: depth, usage: &admission)
                let value = try numerator.divided(by: divisor, maximumDepth: depth, usage: &admission)
                    .outward(maximumCoefficientWidth: maximumCoefficientWidth, maximumDepth: depth, usage: &admission)
                switch axis { case 0: x.append(value); case 1: y.append(value); default: z.append(value) }
            }
            if order < throughOrder {
                let scale = try OriginalSingularFieldElement.constant(.natural(order + 1, usage: &admission),
                    in: context, maximumDepth: depth, usage: &admission)
                let scaledWeightDerivative = try weightDerivative.multiplied(by:
                    .constant(scale, maximumDepth: depth, usage: &admission), maximumDepth: depth, usage: &admission)
                try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldPlanePolynomial.self, usage: &admission)
                var next: [OriginalSingularFieldPlanePolynomial] = []; next.reserveCapacity(3)
                for numerator in row {
                    next.append(try numerator.differentiated(alongU: true, maximumDepth: depth, usage: &admission)
                        .multiplied(by: weight, maximumDepth: depth, usage: &admission)
                        .subtracting(numerator.multiplied(by: scaledWeightDerivative,
                            maximumDepth: depth, usage: &admission), maximumDepth: depth, usage: &admission))
                }
                row = next
                denominator = try denominator.multiplied(by: weight, maximumDepth: depth, usage: &admission)
            }
        }
        self.homogeneous = homogeneous; self.lowerParameter = lowerParameter; self.upperParameter = upperParameter
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
        jet = .init(x: .init(derivatives: x), y: .init(derivatives: y), z: .init(derivatives: z))
    }
}
