import CADCore

/// Original normalized UV law; the third coordinate is exactly zero.
public struct OriginalAffinePcurveSnapshot: OriginalRetainedCurveSourceReading {
    public typealias Field = OriginalExactScalarDomain
    public let original: SurfaceParameterCurve
    public let originalField: Field
    public let originalPolynomials: ExactPolynomialDomain<Field>
    public let originalProofDepth: ExactScalarDepth
    private let position: [ExactPolynomial<Field>]
    private let lower: Field.Value
    private let upper: Field.Value
    public var originalCellCount: Int { 1 }
    public func originalCellLowerBound(at index: Int) -> Field.Value { lower }
    public func originalCellUpperBound(at index: Int) -> Field.Value { upper }
    public func originalCellHomogeneous(at index: Int) -> [ExactPolynomial<Field>] { position }
    init(original: SurfaceParameterCurve, field: Field, polynomials: ExactPolynomialDomain<Field>,
        position: [ExactPolynomial<Field>], lower: Field.Value, upper: Field.Value, depth: ExactScalarDepth) {
        self.original=original; originalField=field; originalPolynomials=polynomials
        self.position=position; self.lower=lower; self.upper=upper; originalProofDepth=depth
    }
}
