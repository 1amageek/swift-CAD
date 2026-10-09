#if SOURCE_ISSUED_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
@testable import DI
#elseif ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Complete parameter coverage and original issued laws share immutable owners.
public struct OriginalIssuedDomainCover<Source: Sendable, Selection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable {
    public let laws: [OriginalRationalChartReceipt<Source, Selection, Field>]
    public let coverage: OriginalDomainCover<Source, Field>
    public let charts: [OriginalIssuedDomainChart<Source, Field>]
    init(laws: [OriginalRationalChartReceipt<Source, Selection, Field>],
        coverage: OriginalDomainCover<Source, Field>, charts: [OriginalIssuedDomainChart<Source, Field>]) {
        self.laws = laws; self.coverage = coverage; self.charts = charts
    }
}
