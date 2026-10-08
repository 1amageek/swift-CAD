#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct OriginalParameterPeriodicLift<Source: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let transport: OriginalParameterTransport<Source,F>
    public let period: OriginalSourcePeriodReceipt<Source,F>
    public let cycle: OriginalParameterCycle
    init(transport: OriginalParameterTransport<Source,F>, period: OriginalSourcePeriodReceipt<Source,F>, cycle: OriginalParameterCycle) {
        self.transport = transport; self.period = period; self.cycle = cycle
    }
}
