#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Conformers return validated immutable snapshots, never mutable source aliases.
public protocol OriginalSourceSnapshotting: Sendable {
    associatedtype Input: Sendable
    associatedtype Source: Sendable
    func snapshot<A: ExactScalarAdmission & ~Copyable>(
        _ input: borrowing Input, limits: OriginalSourceIssuanceLimits,
        using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<Source>
}
