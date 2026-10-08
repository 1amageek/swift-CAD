import CADCore

/// The Native surface capability is explicit; other families use their own provider.
public struct OriginalNativeSurfaceFamilySnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Surface3D,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<BSplineSurface3D> {
        guard case .bSpline(let source) = copy input else { throw .unsupportedRepresentation }
        return try OriginalBSplineSurfaceSnapshotProvider(tolerance: tolerance)
            .snapshot(source, limits: limits, using: &admission)
    }
}
