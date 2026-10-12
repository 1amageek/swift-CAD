/// A verified unique selector over retained original parent coefficients.
public struct OriginalScalarSelectedRootReceipt: Sendable {
    public let coefficients: [OriginalExactScalar]
    public let field: OriginalExactScalarDomain
    public let value: OriginalExactScalar
    public let lower: ExactRationalCoefficient
    public let upper: ExactRationalCoefficient
    public let axis: ExactScalarRootAxis

    init(coefficients: [OriginalExactScalar], field: OriginalExactScalarDomain,
        value: OriginalExactScalar, lower: ExactRationalCoefficient,
        upper: ExactRationalCoefficient, axis: ExactScalarRootAxis) {
        self.coefficients = coefficients; self.field = field; self.value = value
        self.lower = lower; self.upper = upper; self.axis = axis
    }
}
