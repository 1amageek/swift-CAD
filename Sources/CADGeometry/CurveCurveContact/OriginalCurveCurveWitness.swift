import CADCore

/// Exact homogeneous equality at an original, representable native parameter pair.
struct OriginalCurveCurveWitness {
    private typealias Expansion = [Double]

    func witness(first: BSplineCurve3D, firstSpan: RationalBezierCurveJetEncloser.NativeSpan,
        firstRange: ScalarInterval, second: BSplineCurve3D,
        secondSpan: RationalBezierCurveJetEncloser.NativeSpan, secondRange: ScalarInterval,
        budget: inout NativeCurveCurveContactBudget) throws -> (Double, Double)? {
        let firstParameters = [firstRange.lower, firstRange.midpoint, firstRange.upper]
        let secondParameters = [secondRange.lower, secondRange.midpoint, secondRange.upper]
        for a in firstParameters {
            guard let firstValue = try homogeneous(first, span: firstSpan, parameter: a, budget: &budget) else { continue }
            for b in secondParameters {
                guard let secondValue = try homogeneous(second, span: secondSpan, parameter: b, budget: &budget) else { continue }
                var equal = true
                for axis in 0..<3 {
                    guard let lhs = try multiply(firstValue[axis], secondValue[3], budget: &budget),
                          let rhs = try multiply(secondValue[axis], firstValue[3], budget: &budget) else { equal = false; break }
                    try budget.work(lhs.count + rhs.count)
                    if FloatingPointExpansion.sign(FloatingPointExpansion.subtract(lhs, rhs)) != .zero { equal = false; break }
                }
                if equal { return (a, b) }
            }
        }
        return nil
    }

    private func homogeneous(_ source: BSplineCurve3D,
        span: RationalBezierCurveJetEncloser.NativeSpan, parameter: Double,
        budget: inout NativeCurveCurveContactBudget) throws -> [Expansion]? {
        try homogeneous(source, nativeIndex: span.index,
            nativeDomain: ScalarInterval(lower: span.lower, upper: span.upper), parameter: parameter, budget: &budget)
    }

    func homogeneous(_ source: BSplineCurve3D, nativeIndex index: Int,
        nativeDomain: ScalarInterval, parameter: Double,
        budget: inout NativeCurveCurveContactBudget) throws -> [[Double]]? {
        guard index >= source.degree, index < source.controlPointCount,
              source.knots[(index - source.degree + 1)...index].allSatisfy({ $0 == nativeDomain.lower }),
              source.knots[(index + 1)...(index + source.degree)].allSatisfy({ $0 == nativeDomain.upper }) else { return nil }
        let q = (parameter - nativeDomain.lower) / nativeDomain.width
        guard q.isFinite, q >= 0, q <= 1,
              let scaled = try multiply([q], FloatingPointExpansion.difference(nativeDomain.upper, nativeDomain.lower), budget: &budget),
              FloatingPointExpansion.sign(FloatingPointExpansion.subtract(
                FloatingPointExpansion.difference(parameter, nativeDomain.lower), scaled)) == .zero else { return nil }
        var result: [Expansion] = []
        try budget.work(4)
        for axis in 0..<4 {
            try budget.work(source.degree + 1)
            var level: [Expansion] = []
            for control in (index - source.degree)...index {
                let p = source.controlPoints[control]
                let weight = source.weights[control]
                if axis == 3 { level.append([weight]); continue }
                let coordinate = axis == 0 ? p.x : axis == 1 ? p.y : p.z
                guard let value = try multiply([coordinate], [weight], budget: &budget) else { return nil }
                level.append(value)
            }
            var count = level.count
            while count > 1 {
                for i in 0..<(count - 1) {
                    guard let a = try multiply(level[i], FloatingPointExpansion.difference(1, q), budget: &budget),
                          let b = try multiply(level[i + 1], [q], budget: &budget) else { return nil }
                    try budget.work(a.count + b.count)
                    level[i] = FloatingPointExpansion.sum(a, b)
                }
                count -= 1
            }
            result.append(level[0])
        }
        return result
    }

    func multiply(_ lhs: [Double], _ rhs: [Double],
        budget: inout NativeCurveCurveContactBudget) throws -> [Double]? {
        let pairs = lhs.count.multipliedReportingOverflow(by: rhs.count)
        let doubled = pairs.partialValue.multipliedReportingOverflow(by: 2)
        let factor = doubled.partialValue.addingReportingOverflow(1)
        let work = pairs.partialValue.multipliedReportingOverflow(by: factor.partialValue)
        guard !pairs.overflow, !doubled.overflow, !factor.overflow, !work.overflow else { throw budget.exhausted() }
        try budget.work(work.partialValue)
        for a in lhs where a != 0 {
            for b in rhs where b != 0 {
                // Dekker products need normal intermediates. Refusing an unsafe
                // exact witness does not certify a zero or alter the original jet path.
                guard a.isFinite, b.isFinite, abs(a.exponent) <= 450, abs(b.exponent) <= 450,
                      a.exponent + b.exponent > -900, a.exponent + b.exponent < 900 else { return nil }
            }
        }
        let result = FloatingPointExpansion.product(lhs, rhs)
        return result.allSatisfy({ $0.isFinite }) ? result : nil
    }
}
