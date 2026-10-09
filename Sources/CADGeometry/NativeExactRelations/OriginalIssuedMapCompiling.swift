#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

/// Transfers a complete selected law cover into the existing L5 map contract.
public protocol OriginalIssuedMapCompiling: Sendable {
    associatedtype Source: Sendable
    associatedtype Selection: Sendable
    func compile<A: ExactScalarAdmission & ~Copyable>(
        cover: borrowing OriginalIssuedDomainCover<Source, Selection, OriginalExactScalarDomain>,
        field: borrowing ExactAlgebraicScalarDomain<OriginalExactScalarDomain>,
        coefficientTransfer: OriginalScalarTransferReceipt?, maximumMaps: Int,
        using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalIssuedMapPreparation<Source, Selection>
}
