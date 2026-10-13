import CADCore

/// Retains the actual lift alternative for existing curve-child source consumers.
public struct OriginalNativeSurfaceLiftCurveSnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Curve3D,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalNativeSurfaceLiftSnapshot> {
        let input = copy input
        do {
            try admission.checkpoint()
            try admission.consumeWork(1)
            guard case .surfaceLift(let lift) = input else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            return try OriginalNativeSurfaceLiftSnapshotProvider(tolerance: tolerance)
                .snapshot(lift, limits: limits, using: &admission)
        } catch { throw .init(preserving: error) }
    }
}
