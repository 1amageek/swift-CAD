import CADCore

extension OriginalPlaneDerivativeSurfaceSnapshotProvider: OriginalRetainedLiftHostSnapshotting {
    public typealias Source = OriginalPlaneDerivativeSurfaceSnapshot
    public func bindHost<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Surface3D,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceBinding<Source> {
        let input=copy input
        do {
            try admission.checkpoint();try admission.consumeWork(1)
            guard case .procedural(.originalPlaneDerivative(let host)) = input else {
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            return try DefaultOriginalSourceBindingIssuer(provider:self).bind(host,limits:limits,using:&admission)
        } catch { throw .init(preserving:error) }
    }
}
