import CADCore

/// Retains exact projected coordinates together with their original source authority.
package struct OriginalDraftedProjectionSnapshot: OriginalRetainedSurfaceSourceReading {
    package typealias Field=OriginalExactScalarDomain
    package let original: OriginalDraftedCoordinateProjection
    package let originalField: Field
    package let originalPolynomials: ExactPolynomialDomain<Field>
    package let originalProofDepth: ExactScalarDepth
    package let cells:[OriginalRetainedSurfaceCell<Field>]
    package var originalCellCount:Int { cells.count }
    package func originalCellLowerBound(at index:Int,axis:Int)->Field.Value { cells[index].support[axis].lower }
    package func originalCellUpperBound(at index:Int,axis:Int)->Field.Value { cells[index].support[axis].upper }
    package func originalCellHomogeneous(at index:Int)->[ExactPolynomial<Field>] { cells[index].homogeneous }
}
