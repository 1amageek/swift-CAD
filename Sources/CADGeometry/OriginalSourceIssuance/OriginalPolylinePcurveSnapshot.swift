import CADCore

/// Complete normalized UV cells retaining the original Euclidean station owner.
public struct OriginalPolylinePcurveSnapshot: OriginalRetainedCurveSourceReading {
    public typealias Field = OriginalExactScalarDomain
    public let original: SurfaceParameterCurve
    public let originalField: Field
    public let originalPolynomials: ExactPolynomialDomain<Field>
    public let originalProofDepth: ExactScalarDepth
    private let law: OriginalEuclideanPolylineParameterLaw
    private let positions: [[ExactPolynomial<Field>]]
    private let bounds: [OriginalSourceParameterInterval<Field.Value>]
    public var originalCellCount: Int { positions.count }
    public func originalCellLowerBound(at index: Int) -> Field.Value { bounds[index].lower }
    public func originalCellUpperBound(at index: Int) -> Field.Value { bounds[index].upper }
    public func originalCellHomogeneous(at index: Int) -> [ExactPolynomial<Field>] { positions[index] }
    public func originalPointIndex(at index: Int) -> Int { law.segments[index].originalPointIndex }

    init(original: SurfaceParameterCurve, law: OriginalEuclideanPolylineParameterLaw,
        field: Field, polynomials: ExactPolynomialDomain<Field>, depth: ExactScalarDepth,
        positions: [[ExactPolynomial<Field>]], bounds: [OriginalSourceParameterInterval<Field.Value>]) {
        self.original=original; self.law=law; originalField=field
        originalPolynomials=polynomials; originalProofDepth=depth
        self.positions=positions; self.bounds=bounds
    }
}
