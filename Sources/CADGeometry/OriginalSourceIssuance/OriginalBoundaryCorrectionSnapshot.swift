import CADCore

/// Retains the actual constructor and the single original positional producer.
public struct OriginalBoundaryCorrectionSnapshot:OriginalRetainedSurfaceSourceReading {
    public typealias Field=OriginalExactScalarDomain
    public let original:OriginalBoundaryCorrectedSurface3D
    public let originalField:Field
    public let originalPolynomials:ExactPolynomialDomain<Field>
    public let originalProofDepth:ExactScalarDepth
    private let atlas:OriginalCoonsRationalDifferentialAtlas
    private let cells:[OriginalRetainedSurfaceCell<Field>]
    public var originalCellCount:Int { cells.count }
    public func originalCellLowerBound(at index:Int,axis:Int)->Field.Value { cells[index].support[axis].lower }
    public func originalCellUpperBound(at index:Int,axis:Int)->Field.Value { cells[index].support[axis].upper }
    public func originalCellHomogeneous(at index:Int)->[ExactPolynomial<Field>] { cells[index].homogeneous }
    init(original:OriginalBoundaryCorrectedSurface3D,field:Field,polynomials:ExactPolynomialDomain<Field>,
        atlas:OriginalCoonsRationalDifferentialAtlas,proofDepth:ExactScalarDepth,cells:[OriginalRetainedSurfaceCell<Field>]) {
        self.original=original;self.originalField=field;self.originalPolynomials=polynomials
        self.originalProofDepth=proofDepth;self.atlas=atlas;self.cells=cells
    }
}
