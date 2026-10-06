import CADCore

/// An immutable exact tuple handle retaining its original source and field owners.
public struct OriginalAffineCurveSurfacePoint: Sendable {
    package let owner: OriginalAffineCurveSurfacePoints
    public let ordinal: Int

    package init(owner: OriginalAffineCurveSurfacePoints, ordinal: Int) {
        self.owner = owner; self.ordinal = ordinal
    }

    /// Coordinate order is native curve T, unchanged Native surface U and V.
    public func parameter(axis: Int, in receipt: OriginalAffineCurveSurfacePoints) throws -> OriginalAlgebraicCoordinate {
        guard receipt.owns(self) else {
            throw GeometryConversionError.invalidInput("Original tuple access requires its owning receipt.")
        }
        return try owner.coordinate(at: ordinal, axis: axis)
    }

    public func compareParameter<B: RationalAlgebraAdmitting>(axis: Int,
        to station: ExactRationalCoefficient, in receipt: OriginalAffineCurveSurfacePoints,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        guard receipt.owns(self), (0..<3).contains(axis), (0...32).contains(maximumAlgebraicDepth) else {
            throw GeometryConversionError.invalidInput("Original tuple comparison requires its owner, coordinate and caller depth.")
        }
        return try owner.isolation(at: ordinal, axis: axis).compared(to: station,
            maximumDepth: maximumAlgebraicDepth, usage: &usage).sign
    }
}
