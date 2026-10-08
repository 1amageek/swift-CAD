/// Explicit, proof-preserving transport; ordinary importing remains owner-bound.
public protocol OriginalScalarTransferring: Sendable {
    func transfer<A: ExactScalarAdmission & ~Copyable>(
        _ sources: borrowing [OriginalExactScalar],
        into destination: borrowing OriginalExactScalarDomain,
        using admission: inout A
    ) throws(ExactScalarFailure) -> OriginalScalarTransferReceipt

    func bindSelectedRoot<A: ExactScalarAdmission & ~Copyable>(
        coefficients: borrowing [OriginalExactScalar],
        in parent: borrowing OriginalExactScalarDomain,
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient,
        includesLower: Bool, includesUpper: Bool, depth: ExactScalarDepth,
        axis: ExactScalarRootAxis, using admission: inout A
    ) throws(ExactScalarFailure) -> OriginalScalarSelectedRootReceipt

    func importing<A: ExactScalarAdmission & ~Copyable>(
        _ value: borrowing OriginalExactScalar,
        through receipt: borrowing OriginalScalarTransferReceipt, using admission: inout A
    ) throws(ExactScalarFailure) -> OriginalExactScalar
}
