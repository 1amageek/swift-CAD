/// Selected original native curve bounds without widening its owning rational domain.
package struct OriginalRationalCurveIntervalJet: Sendable {
    package let original: OriginalRationalCurvePolynomial
    package let parameterMap: OriginalCurveAffineParameterMap
    package let normalizedLower: ExactRationalCoefficient
    package let normalizedUpper: ExactRationalCoefficient
    package let rawLower: ExactRationalCoefficient
    package let rawUpper: ExactRationalCoefficient
    package let jet: IntervalVectorDerivativeJet

    package init<B: RationalAlgebraAdmitting>(original: OriginalRationalCurvePolynomial,
        parameterMap: OriginalCurveAffineParameterMap,
        normalizedLower: ExactRationalCoefficient, normalizedUpper: ExactRationalCoefficient,
        throughOrder: Int, usage: inout B) throws {
        guard (0...3).contains(throughOrder), !parameterMap.gain.isZero,
              !(try normalizedUpper.subtracting(normalizedLower, usage: &usage)).isNegative else {
            throw rationalAlgebraFailure("Selected original curve jet needs ordered exact bounds and a nonzero affine parameter gain.")
        }
        let first = try parameterMap.gain.multiplied(by: normalizedLower, usage: &usage)
            .adding(parameterMap.offset, usage: &usage)
        let last = try parameterMap.gain.multiplied(by: normalizedUpper, usage: &usage)
            .adding(parameterMap.offset, usage: &usage)
        let lower = parameterMap.gain.isNegative ? last : first
        let upper = parameterMap.gain.isNegative ? first : last
        guard !(try lower.subtracting(original.lowerParameter, usage: &usage)).isNegative,
              !(try original.upperParameter.subtracting(upper, usage: &usage)).isNegative else {
            throw rationalAlgebraFailure("Exact normalized query is outside its selected original native knot owner.")
        }
        let derivatives = try OriginalRationalCurveDerivativeLaw(original: original,
            throughOrder: throughOrder, usage: &usage)
        let count = try rationalAlgebraCount(throughOrder, 1)
        try RationalAlgebraStorage.retain(try rationalAlgebraCount(count, 3, multiply: true),
            of: OutwardScalarInterval.self, usage: &usage)
        var x: [OutwardScalarInterval] = [], y: [OutwardScalarInterval] = [], z: [OutwardScalarInterval] = []
        x.reserveCapacity(count); y.reserveCapacity(count); z.reserveCapacity(count)
        var gainPower = ExactRationalCoefficient.one
        for order in 0...throughOrder {
            try usage.consumeExactWork(1)
            let denominator = try OriginalRationalPolynomialRange(original: derivatives.denominators[order],
                lower: lower, upper: upper, usage: &usage)
            for axis in 0..<3 {
                let numerator = try OriginalRationalPolynomialRange(original: derivatives.numerators[order][axis],
                    lower: lower, upper: upper, usage: &usage)
                let value = try numerator.divided(by: denominator, usage: &usage)
                    .scaled(by: gainPower, usage: &usage).outward(usage: &usage)
                switch axis { case 0: x.append(value); case 1: y.append(value); default: z.append(value) }
            }
            if order < throughOrder {
                gainPower = try gainPower.multiplied(by: parameterMap.gain, usage: &usage)
            }
        }
        self.original = original; self.parameterMap = parameterMap
        self.normalizedLower = normalizedLower; self.normalizedUpper = normalizedUpper
        rawLower = lower; rawUpper = upper
        jet = .init(x: .init(derivatives: x), y: .init(derivatives: y), z: .init(derivatives: z))
    }
}
