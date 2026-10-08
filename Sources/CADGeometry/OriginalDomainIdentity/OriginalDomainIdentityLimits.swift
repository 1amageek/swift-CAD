#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct OriginalDomainIdentityLimits: Sendable {
    public let source: OriginalSourceIssuanceLimits
    public let maximumTransportDepth: Int
    public let maximumCharts: Int
    public let maximumFamilies: Int
    public let maximumIdentityProofs: Int
    public init(source: OriginalSourceIssuanceLimits, maximumTransportDepth: Int,
        maximumCharts: Int, maximumFamilies: Int, maximumIdentityProofs: Int) throws(OriginalDomainIdentityFailure) {
        guard maximumTransportDepth >= 0, maximumCharts >= 0, maximumFamilies >= 0,
            maximumIdentityProofs >= 0 else { throw .invalidDomain }
        self.source = source; self.maximumTransportDepth = maximumTransportDepth
        self.maximumCharts = maximumCharts; self.maximumFamilies = maximumFamilies
        self.maximumIdentityProofs = maximumIdentityProofs
    }
}
