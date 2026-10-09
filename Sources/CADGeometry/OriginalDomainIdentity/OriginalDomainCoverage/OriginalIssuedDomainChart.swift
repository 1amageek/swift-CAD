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

/// A retained template index and its exact selected local/original correspondence.
public struct OriginalIssuedDomainChart<Source: Sendable, Field: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let lawIndex: Int
    public let selectedLocal: OriginalParameterSelection<Source, Field>
    public let transport: OriginalParameterTransport<Source, Field>
    init(lawIndex: Int, selectedLocal: OriginalParameterSelection<Source, Field>,
        transport: OriginalParameterTransport<Source, Field>) {
        self.lawIndex = lawIndex; self.selectedLocal = selectedLocal; self.transport = transport
    }
}
