import CADCore

/// Exact original one-sided quotient derivatives at native joins and seams.
struct OriginalCurveHigherContinuity {
    private struct Usage: RationalAlgebraAdmitting {
        let consume: () throws -> Void
        let maximumDepth: Int
        let storage: ((Int) throws -> Void)?
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0 else { throw GeometryConversionError.invalidInput("Original exact curve work count is negative.") }
            for _ in 0..<count { try CurrentTaskCancellationChecker().checkCancellation(); try consume() }
        }
        mutating func retainExactStorage(_ count: Int) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
            guard count >= 0, !bytes.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original join storage overflows.") }
            if let storage { try storage(bytes.partialValue) } else { try consumeExactWork(count) }
        }
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= maximumDepth else {
                throw GeometryConversionError.resourceLimitExceeded("Original exact curve join exceeded caller depth.")
            }
            try consumeExactWork(1)
        }
    }

    static func prove(source: BSplineCurve3D, leftSpan: Int, rightSpan: Int,
        leftParameter: Double, rightParameter: Double, throughOrder: Int,
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws {
        try withoutActuallyEscaping(consumeWork) { scoped in
        var usage = Usage(consume: scoped, maximumDepth: maximumSubdivisionDepth, storage: consumeStorage)
        let left = try OriginalRationalCurveDerivativeLaw(original:
            OriginalRationalCurvePolynomial(source: source, spanIndex: leftSpan,
                tolerance: tolerance, usage: &usage), throughOrder: throughOrder, usage: &usage)
        let right = try OriginalRationalCurveDerivativeLaw(original:
            OriginalRationalCurvePolynomial(source: source, spanIndex: rightSpan,
                tolerance: tolerance, usage: &usage), throughOrder: throughOrder, usage: &usage)
        let a = try ExactRationalCoefficient.originalDouble(leftParameter, usage: &usage)
        let b = try ExactRationalCoefficient.originalDouble(rightParameter, usage: &usage)
        for order in 0...throughOrder {
            let wa = try left.denominators[order].evaluated(atU: a, v: .zero, usage: &usage)
            let wb = try right.denominators[order].evaluated(atU: b, v: .zero, usage: &usage)
            guard wa.isPositive, wb.isPositive else {
                throw GeometryConversionError.invalidInput("Original curve join has no positive original denominator.")
            }
            for axis in 0..<3 {
                let lhs = try left.numerators[order][axis].evaluated(atU: a, v: .zero, usage: &usage)
                    .multiplied(by: wb, usage: &usage)
                let rhs = try right.numerators[order][axis].evaluated(atU: b, v: .zero, usage: &usage)
                    .multiplied(by: wa, usage: &usage)
                guard try lhs.subtracting(rhs, usage: &usage).isZero else {
                    throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                        message: "Original requested derivative is discontinuous at this native curve join.")
                }
            }
        }
        }
    }
}
