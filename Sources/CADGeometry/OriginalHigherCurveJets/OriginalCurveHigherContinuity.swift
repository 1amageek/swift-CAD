import CADCore

/// Exact original one-sided quotient derivatives at native joins and seams.
struct OriginalCurveHigherContinuity {
    static func prove(source: BSplineCurve3D, leftSpan: Int, rightSpan: Int,
        leftParameter: Double, rightParameter: Double, throughOrder: Int,
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        let left = try OriginalRationalCurveDerivativeLaw(original:
            OriginalRationalCurvePolynomial(source: source, spanIndex: leftSpan,
                tolerance: tolerance, usage: &execution), throughOrder: throughOrder, usage: &execution)
        let right = try OriginalRationalCurveDerivativeLaw(original:
            OriginalRationalCurvePolynomial(source: source, spanIndex: rightSpan,
                tolerance: tolerance, usage: &execution), throughOrder: throughOrder, usage: &execution)
        let a = try ExactRationalCoefficient.originalDouble(leftParameter, usage: &execution)
        let b = try ExactRationalCoefficient.originalDouble(rightParameter, usage: &execution)
        for order in 0...throughOrder {
            let wa = try left.denominators[order].evaluated(atU: a, v: .zero, usage: &execution)
            let wb = try right.denominators[order].evaluated(atU: b, v: .zero, usage: &execution)
            guard wa.isPositive, wb.isPositive else {
                throw GeometryConversionError.invalidInput("Original curve join has no positive original denominator.")
            }
            for axis in 0..<3 {
                let lhs = try left.numerators[order][axis].evaluated(atU: a, v: .zero, usage: &execution)
                    .multiplied(by: wb, usage: &execution)
                let rhs = try right.numerators[order][axis].evaluated(atU: b, v: .zero, usage: &execution)
                    .multiplied(by: wa, usage: &execution)
                guard try lhs.subtracting(rhs, usage: &execution).isZero else {
                    throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                        message: "Original requested derivative is discontinuous at this native curve join.")
                }
            }
        }
    }
}
