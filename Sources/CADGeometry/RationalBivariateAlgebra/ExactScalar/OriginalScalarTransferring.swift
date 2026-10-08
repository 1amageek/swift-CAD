/// Explicit, proof-preserving transport; ordinary importing remains owner-bound.
public protocol OriginalScalarTransferring: Sendable {
    func transfer<A: ExactScalarAdmission & ~Copyable>(
        _ sources: borrowing [OriginalExactScalar],
        into destination: borrowing OriginalExactScalarDomain,
        using admission: inout A
    ) throws(ExactScalarFailure) -> OriginalScalarTransferReceipt
}
