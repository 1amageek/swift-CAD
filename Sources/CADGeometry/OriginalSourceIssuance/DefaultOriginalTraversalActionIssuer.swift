#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalTraversalActionIssuer<S: OriginalTraversalSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering>: OriginalSourceAffineActionIssuing {
    public typealias Source = S
    public typealias Field = F
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,field: borrowing F,
        limits: OriginalSourceIssuanceLimits,using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceAffineActionReceipt<S,F> {
        let source = copy source,field = copy field
        return try OriginalSourceAffineActionBuilder.issue(source:source,field:field,limits:limits,using:&admission) { row,column,a in
            try field.integer(row == column ? 1:0,using:&a)
        }
    }
}
