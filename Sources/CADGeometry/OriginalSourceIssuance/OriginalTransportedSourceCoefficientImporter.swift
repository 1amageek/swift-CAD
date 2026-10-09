#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Retains a proved source-owner embedding; numeric equality never authorizes import.
public struct OriginalTransportedSourceCoefficientImporter: OriginalSourceCoefficientImporting {
    public typealias Field = OriginalExactScalarDomain
    public let transfer: OriginalScalarTransferReceipt
    public init(transfer: OriginalScalarTransferReceipt) { self.transfer = transfer }
    public func importing<A: ExactScalarAdmission & ~Copyable>(
        _ value: borrowing OriginalExactScalar, into field: borrowing OriginalExactScalarDomain,
        using admission: inout A
    ) throws(ExactScalarFailure) -> OriginalExactScalar {
        let mapped = try DefaultOriginalScalarTransporter().importing(value, through: transfer, using: &admission)
        return try field.importing(mapped, using: &admission)
    }
}
