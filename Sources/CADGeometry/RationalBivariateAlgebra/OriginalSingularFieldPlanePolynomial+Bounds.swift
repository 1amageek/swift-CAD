import CADCore

extension OriginalSingularFieldPlanePolynomial {
    /// Whole local-box original partials; field coefficient bounds are exact outward enclosures.
    package func partial(over box: SurfaceParameterBox, uOrder: Int, vOrder: Int,
        maximumCoefficientWidth: ExactRationalCoefficient? = nil, inheritedDepth: Int = 0,
        maximumDepth: Int, usage: inout some RationalAlgebraAdmitting) throws -> OutwardScalarInterval {
        guard uOrder >= 0, vOrder >= 0 else { throw rationalAlgebraFailure("Negative original local partial order.") }
        var result = OutwardScalarInterval.exact(0)
        let u = OutwardScalarInterval(lower: box.u.lower, upper: box.u.upper)
        let v = OutwardScalarInterval(lower: box.v.lower, upper: box.v.upper)
        for (power, value) in try orderedTerms(usage: &usage) where power.u >= uOrder && power.v >= vOrder {
            var scale = ExactRationalCoefficient.one
            if uOrder > 0 { for j in 0..<uOrder { scale = try scale.multiplied(by: .natural(power.u - j, usage: &usage), usage: &usage) } }
            if vOrder > 0 { for j in 0..<vOrder { scale = try scale.multiplied(by: .natural(power.v - j, usage: &usage), usage: &usage) } }
            var bound = try value.enclosure(maximumWidth: maximumCoefficientWidth, inheritedDepth: inheritedDepth,
                maximumDepth: maximumDepth, usage: &usage)
                * scale.outwardInterval(usage: &usage)
            for _ in 0..<(power.u - uOrder) { try usage.consumeExactWork(1); bound = bound * u }
            for _ in 0..<(power.v - vOrder) { try usage.consumeExactWork(1); bound = bound * v }
            try usage.consumeExactWork(1); result = result + bound
        }
        guard result.isFinite else { throw KernelError(phase: .geometry, code: .intersectionFailure,
            tolerance: nil, message: "Original local algebraic partial has no finite outward binary enclosure.") }
        return result
    }
}
