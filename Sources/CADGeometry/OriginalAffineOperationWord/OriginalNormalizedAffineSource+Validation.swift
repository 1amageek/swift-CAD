import CADCore

extension OriginalNormalizedAffineSource {
    func validateOriginalPayload<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws {
        try usage.consumeWork(9)
        try location.validate()
        if let axis1 { try usage.consumeWork(3); try axis1.validate() }
        if let axis2 { try usage.consumeWork(3); try axis2.validate() }
        if let axis3 { try usage.consumeWork(3); try axis3.validate() }
        if let scale {
            guard scale.isFinite, scale > 0 else { throw rationalAlgebraFailure("Original normalized scale must be finite and positive.") }
        }
        if family == .axis2, axis2 != nil || scale != nil {
            throw rationalAlgebraFailure("Original axis-placement source contains Cartesian fields.")
        }
        guard lengthGain.isPositive, linearGain.isPositive else {
            throw rationalAlgebraFailure("Original normalized unit gains must be positive.")
        }
        try gainPayload(lengthGain, usage: &usage)
        try gainPayload(linearGain, usage: &usage)
        for adjustment in adjustments {
            try usage.consumeWork(4)
            try adjustment.displacement.validate()
        }
    }
    private func gainPayload<B: ExactScalarAdmission & ~Copyable>(_ gain: ExactRationalCoefficient, usage: inout B) throws {
        try usage.consumeWork(1)
        for _ in gain.canonicalNumeratorWords { try usage.consumeWork(1) }
        for _ in gain.canonicalDenominatorWords { try usage.consumeWork(1) }
    }
}
