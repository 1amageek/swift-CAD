import CADCore

/// Extracts a supported original host and delegates to its retained source producer.
public protocol OriginalRetainedLiftHostSnapshotting: Sendable {
    associatedtype Source: OriginalRetainedSurfaceSourceReading where Source.Field == OriginalExactScalarDomain
    func bindHost<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Surface3D,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceBinding<Source>
}
