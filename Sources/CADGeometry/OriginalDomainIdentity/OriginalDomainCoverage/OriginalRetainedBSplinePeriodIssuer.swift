#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Reuses sealed source authority when the domain issuer checks its own frame.
struct OriginalRetainedBSplinePeriodIssuer<S: OriginalBSplineSourceReading>: OriginalSourcePeriodIssuing {
    typealias Source=S
    typealias Field=OriginalExactScalarDomain
    let periods: [OriginalSourcePeriodReceipt<S,Field>]
    func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,axis: Int,
        field: Field,limits: OriginalSourceIssuanceLimits,using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourcePeriodReceipt<S,Field> {
        do {
            _=try source.chart(axis,limits:limits,using:&a)
            for period in periods {
                try a.consumeWork(1)
                if period.axis==axis {
                    guard source.owns(period.anchor) else { throw OriginalSourceIssuanceFailure.foreignBinding }
                    _=try field.sign(of:period.lower,using:&a)
                    _=try field.sign(of:period.upper,using:&a)
                    _=try field.sign(of:period.period,using:&a)
                    try a.checkpoint();return period
                }
            }
            throw OriginalSourceIssuanceFailure.unresolvedAuthority
        } catch let error as OriginalSourceIssuanceFailure { throw error }
        catch let error as ExactScalarFailure { throw .scalar(error) }
        catch { throw .sourceRejected(error) }
    }
}
