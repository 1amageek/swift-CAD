import CADCore

/// An exact tuple handle; every coordinate retains the same complete source receipt.
public struct OriginalNativeSurfaceSurfacePoint: Sendable {
    package let owner: OriginalNativeSurfaceSurfacePoints
    public let ordinal: Int

    package init(owner: OriginalNativeSurfaceSurfacePoints, ordinal: Int) {
        self.owner = owner; self.ordinal = ordinal
    }

    /// Coordinate order is original native u1, v1, u2, v2. Foreign receipts are rejected.
    public func compareParameter<B: ExactScalarAdmission & ~Copyable>(axis: Int,
        to station: ExactRationalCoefficient, in receipt: OriginalNativeSurfaceSurfacePoints,
        maximumAlgebraicDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        guard receipt.owns(self), (0..<4).contains(axis), (0...32).contains(maximumAlgebraicDepth) else {
            throw GeometryConversionError.invalidInput("Exact tuple comparison requires its owning receipt and coordinate.")
        }
        let isolation = try owner.parameterIsolation(at: ordinal, axis: axis)
        return try isolation.compared(to: station, maximumDepth: maximumAlgebraicDepth,
            usage: &usage).sign
    }

    public func parameter(axis: Int, in receipt: OriginalNativeSurfaceSurfacePoints) throws -> OriginalAlgebraicCoordinate {
        guard receipt.owns(self), (0..<4).contains(axis) else {
            throw GeometryConversionError.invalidInput("Exact tuple access requires its owning receipt and coordinate.")
        }
        let cell = try owner.cell(at: ordinal)
        let isolation = try owner.parameterIsolation(at: ordinal, axis: axis)
        return .init(original: isolation.original, inheritedDepth: isolation.sourceDepth,
            inheritedCoefficientDepth: max(cell.coefficientAdmissionDepth,
                owner.parameterLocalizations[ordinal * 4 + axis]?.coefficientDepth ?? 0),
            certifiedBounds: (isolation.lower, isolation.upper))
    }
}
