import CADCore

/// The original constructor, constraints and single rational producer remain owned.
public struct OriginalPlaneDerivativeCurveSnapshot:OriginalRetainedCurveSourceReading {
    public typealias Field=OriginalExactScalarDomain
    public let original:OriginalPlaneDerivativeCurve3D
    public let originalField:Field
    public let originalPolynomials:ExactPolynomialDomain<Field>
    public let originalProofDepth:ExactScalarDepth
    private let pieces:[OriginalSplineTraversalPolynomialPiece]
    private let position:[[ExactPolynomial<Field>]]
    private let support:[OriginalSourceParameterInterval<Field.Value>]
    public var originalCellCount:Int { pieces.count }
    public func originalCellLowerBound(at index:Int)->Field.Value { support[index].lower }
    public func originalCellUpperBound(at index:Int)->Field.Value { support[index].upper }
    public func originalCellHomogeneous(at index:Int)->[ExactPolynomial<Field>] { position[index] }
    init(original:OriginalPlaneDerivativeCurve3D,field:Field,polynomials:ExactPolynomialDomain<Field>,proofDepth:ExactScalarDepth,
        pieces:[OriginalSplineTraversalPolynomialPiece],position:[[ExactPolynomial<Field>]],support:[OriginalSourceParameterInterval<Field.Value>]) {
        self.original=original;self.originalField=field;self.originalPolynomials=polynomials;self.originalProofDepth=proofDepth
        self.pieces=pieces;self.position=position;self.support=support
    }
}
