import CADCore

/// An immutable exact tuple handle retaining its original source and field owners.
public struct OriginalCoonsCurveSurfacePoint: Sendable {
    package let owner: OriginalCoonsCurveSurfacePoints
    public let ordinal: Int

    package init(owner: OriginalCoonsCurveSurfacePoints, ordinal: Int) {
        self.owner = owner; self.ordinal = ordinal
    }

    /// Coordinate order is native curve T, original normalized Coons U and V.
    public func parameter(axis: Int, in receipt: OriginalCoonsCurveSurfacePoints) throws -> OriginalAlgebraicCoordinate {
        guard receipt.owns(self) else {
            throw GeometryConversionError.invalidInput("Original tuple access requires its owning receipt.")
        }
        return try owner.coordinate(at: ordinal, axis: axis)
    }

    public func compareParameter<B: ExactScalarAdmission & ~Copyable>(axis: Int,
        to station: ExactRationalCoefficient, in receipt: OriginalCoonsCurveSurfacePoints,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        guard receipt.owns(self), (0..<3).contains(axis), (0...32).contains(maximumAlgebraicDepth) else {
            throw GeometryConversionError.invalidInput("Original tuple comparison requires its owner, coordinate and caller depth.")
        }
        return try owner.isolation(at: ordinal, axis: axis).compared(to: station,
            maximumDepth: maximumAlgebraicDepth, usage: &usage).sign
    }
}
