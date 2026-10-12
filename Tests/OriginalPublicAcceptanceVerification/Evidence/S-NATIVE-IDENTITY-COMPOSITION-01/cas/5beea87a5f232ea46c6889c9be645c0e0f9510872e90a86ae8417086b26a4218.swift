#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalIntrinsicSphereLawIssuer<S: OriginalIntrinsicSphereSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering>: OriginalIntrinsicSphereLawIssuing {
    public typealias Source = S
    public typealias Field = F
    public init() {}
    public func period<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,field: F,
        limits: OriginalSourceIssuanceLimits,using admission: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourcePeriodReceipt<S,F> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1); try source.require(limits)
            let lower = try field.integer(0,using:&admission)
            // This is the exact authored label period, not an approximation of mathematical 2*pi.
            let period = try field.binary64(exactly:2 * Double.pi,using:&admission)
            let anchor = try source.chart(0,limits:limits,using:&admission)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourcePeriodReceipt<S,F>.self))
            let result = OriginalSourcePeriodReceipt(anchor:anchor,field:field,meaning:.intrinsicAngularLabel,axis:0,period:period,lower:lower,upper:period)
            try admission.checkpoint(); return result
        } catch { throw .init(preserving:error) }
    }
    public func pole<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,latitude: F.Value,field: F,
        limits: OriginalSourceIssuanceLimits,using admission: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourcePoleReceipt<S,F> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1); try source.require(limits)
            let quarter = try field.binary64(exactly:Double.pi * 0.5,using:&admission)
            let negative = try field.negated(quarter,using:&admission)
            let north = try field.compare(latitude,quarter,using:&admission) == .equal
            let south = try field.compare(latitude,negative,using:&admission) == .equal
            guard north || south else { throw OriginalSourceIssuanceFailure.invalidChart }
            let radius = try field.binary64(exactly:source.original.radius,using:&admission)
            guard try field.sign(of:radius,using:&admission) == .positive else { throw OriginalSourceIssuanceFailure.invalidSource }
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:F.Value.self))
            var position: [F.Value] = []
            for axis in 0..<3 {
                try admission.consumeWork(1)
                let c = try field.binary64(exactly:source.original.centerCoordinate(in:axis),using:&admission)
                position.append(axis == 2 ? try field.adding(c,north ? radius : field.negated(radius,using:&admission),using:&admission) : c)
            }
            let anchor = try source.chart(north ? 1 : -1,limits:limits,using:&admission)
            try admission.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourcePoleReceipt<S,F>.self))
            let result = OriginalSourcePoleReceipt(anchor:anchor,field:field,latitude:latitude,position:position)
            try admission.checkpoint(); return result
        } catch { throw .init(preserving:error) }
    }
}
