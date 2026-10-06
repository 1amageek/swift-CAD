import CADCore

/// An exact tuple handle; every coordinate retains the same complete source receipt.
public struct OriginalNativeCurveSurfacePoint: Sendable {
    package let owner: OriginalNativeCurveSurfacePoints
    public let ordinal: Int

    package init(owner: OriginalNativeCurveSurfacePoints, ordinal: Int) {
        self.owner = owner; self.ordinal = ordinal
    }

    /// Coordinate order is original native t, u, v. Foreign receipts are rejected.
    public func compareParameter<B: RationalAlgebraAdmitting>(axis: Int,
        to station: ExactRationalCoefficient, in receipt: OriginalNativeCurveSurfacePoints,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        guard receipt.owns(self), (0..<3).contains(axis), (0...32).contains(maximumAlgebraicDepth) else {
            throw GeometryConversionError.invalidInput("Exact tuple comparison requires its owning receipt and coordinate.")
        }
        let isolation = try owner.parameterIsolation(at: ordinal, axis: axis)
        return try isolation.compared(to: station, maximumDepth: maximumAlgebraicDepth,
            usage: &usage).sign
    }

    public func parameter(axis: Int, in receipt: OriginalNativeCurveSurfacePoints) throws -> OriginalAlgebraicCoordinate {
        guard receipt.owns(self), (0..<3).contains(axis) else {
            throw GeometryConversionError.invalidInput("Exact tuple access requires its owning receipt and coordinate.")
        }
        let cell = try owner.cell(at: ordinal)
        let isolation = try owner.parameterIsolation(at: ordinal, axis: axis)
        return .init(original: isolation.original, inheritedDepth: isolation.sourceDepth,
            inheritedCoefficientDepth: max(cell.coefficientAdmissionDepth,
                owner.parameterLocalizations[ordinal * 3 + axis]?.coefficientDepth ?? 0),
            certifiedBounds: (isolation.lower, isolation.upper))
    }
}
