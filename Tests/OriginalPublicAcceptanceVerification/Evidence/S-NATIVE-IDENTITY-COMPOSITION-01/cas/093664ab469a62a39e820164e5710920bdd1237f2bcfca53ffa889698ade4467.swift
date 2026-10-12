#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Cox-de Boor translation follows from every translated knot and repeated
/// homogeneous control, under the validated native source's wrapping semantics.
public struct DefaultOriginalBSplinePeriodIssuer<Source: OriginalBSplineSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering>: OriginalSourcePeriodIssuing {
    public typealias Field = F
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>,
        axis: Int, field: F, limits: OriginalSourceIssuanceLimits, using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourcePeriodReceipt<Source,F> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1); try source.require(limits)
            let s = source.original
            guard (1...2).contains(s.parameterCount), axis >= 0, axis < s.parameterCount,
                s.isPeriodic(in:axis) else { throw OriginalSourceIssuanceFailure.invalidChart }
            let count = s.controlCount(in:axis), degree = s.degree(in:axis), stride = count - degree
            guard degree > 0, stride > 0 else { throw OriginalSourceIssuanceFailure.invalidSource }
            let lo = s.knot(at:degree,in:axis), hi = s.knot(at:count,in:axis)
            let stored = hi - lo
            guard stored.isFinite, stored > 0 else { throw OriginalSourceIssuanceFailure.unresolvedAuthority }
            let lower = try field.binary64(exactly:lo,using:&admission)
            let upper = try field.binary64(exactly:hi,using:&admission)
            let period = try field.binary64(exactly:stored,using:&admission)
            guard try field.compare(field.subtracting(upper,lower,using:&admission),period,using:&admission) == .equal else {
                throw OriginalSourceIssuanceFailure.unresolvedAuthority
            }
            for i in 0..<(s.knotCount(in:axis)-stride) {
                try admission.consumeWork(1)
                let original = try field.binary64(exactly:s.knot(at:i,in:axis),using:&admission)
                let shifted = try field.binary64(exactly:s.knot(at:i+stride,in:axis),using:&admission)
                guard try field.compare(field.subtracting(shifted,original,using:&admission),period,using:&admission) == .equal else {
                    throw OriginalSourceIssuanceFailure.unresolvedAuthority
                }
            }
            let uCount = s.controlCount(in:0), vCount = s.parameterCount == 2 ? s.controlCount(in:1) : 1
            let total = uCount.multipliedReportingOverflow(by:vCount)
            guard !total.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            for index in 0..<total.partialValue {
                try admission.consumeWork(1)
                let coordinate = axis == 0 ? index % uCount : index / uCount
                if coordinate < stride { continue }
                let translated = axis == 0 ? index - stride : index - stride * uCount
                guard try field.compare(field.binary64(exactly:s.weight(ofControl:index),using:&admission),
                    field.binary64(exactly:s.weight(ofControl:translated),using:&admission),using:&admission) == .equal else {
                    throw OriginalSourceIssuanceFailure.unresolvedAuthority
                }
                for component in 0..<3 {
                    try admission.consumeWork(1)
                    guard try field.compare(field.binary64(exactly:s.coordinate(ofControl:index,in:component),using:&admission),
                        field.binary64(exactly:s.coordinate(ofControl:translated,in:component),using:&admission),using:&admission) == .equal else {
                        throw OriginalSourceIssuanceFailure.unresolvedAuthority
                    }
                }
            }
            let anchor = try source.chart(axis,limits:limits,using:&admission)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourcePeriodReceipt<Source,F>.self))
            let result = OriginalSourcePeriodReceipt(anchor:anchor,field:field,meaning:.authoredScalar,axis:axis,period:period,lower:lower,upper:upper)
            try admission.checkpoint(); return result
        } catch { throw .init(preserving:error) }
    }
}
