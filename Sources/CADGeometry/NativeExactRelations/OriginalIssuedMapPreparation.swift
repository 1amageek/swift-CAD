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

/// Original laws and cover survive while map owners share transformed coefficients.
public struct OriginalIssuedMapPreparation<Source: Sendable, Selection: Sendable>: Sendable {
    public let original: OriginalIssuedDomainCover<Source, Selection, OriginalExactScalarDomain>
    public let field: ExactAlgebraicScalarDomain<OriginalExactScalarDomain>
    public let coefficientTransfer: OriginalScalarTransferReceipt?
    public let maps: [OriginalIssuedSelectedMap]
    init(original: OriginalIssuedDomainCover<Source, Selection, OriginalExactScalarDomain>,
        field: ExactAlgebraicScalarDomain<OriginalExactScalarDomain>, maps: [OriginalIssuedSelectedMap], coefficientTransfer: OriginalScalarTransferReceipt?) {
        self.original = original; self.field = field; self.maps = maps
        self.coefficientTransfer = coefficientTransfer
    }
}
