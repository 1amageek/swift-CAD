#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalPlaneBasisIssuer<S: OriginalPlaneSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering>: OriginalPlaneBasisIssuing {
    public typealias Source = S
    public typealias Field = F
    public init() {}
    public func referenceAxis<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        limits: OriginalSourceIssuanceLimits,using a: inout A) throws(OriginalSourceIssuanceFailure) -> Int {
        do {
            try a.checkpoint(); try a.consumeWork(2); try source.require(limits)
            let x = abs(source.original.normalCoordinate(in:0))
            let y = abs(source.original.normalCoordinate(in:1))
            let axis = x <= y ? 0 : 1
            try a.checkpoint(); return axis
        } catch { throw .init(preserving:error) }
    }
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,field f: F,
        firstLength: F.Value,normalLength: F.Value,limits: OriginalSourceIssuanceLimits,using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalPlaneBasisReceipt<S,F> {
        do {
            try a.checkpoint(); try a.consumeWork(1); try source.require(limits)
            guard try f.sign(of:firstLength,using:&a) == .positive,try f.sign(of:normalLength,using:&a) == .positive else { throw OriginalSourceIssuanceFailure.invalidChart }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:9,of:F.Value.self))
            var origin: [F.Value] = [],n: [F.Value] = []
            for i in 0..<3 { try a.consumeWork(1); origin.append(try f.binary64(exactly:source.original.originCoordinate(in:i),using:&a)); n.append(try f.binary64(exactly:source.original.normalCoordinate(in:i),using:&a)) }
            let zero = try f.integer(0,using:&a)
            // The shared source-axis rule avoids parallel axes without normalizing Double values.
            let referenceX = try referenceAxis(source:source,limits:limits,using:&a) == 0
            let cross = referenceX ? [zero,n[2],try f.negated(n[1],using:&a)] : [try f.negated(n[2],using:&a),zero,n[0]]
            func dot(_ x: [F.Value],_ y: [F.Value],_ a: inout A) throws -> F.Value {
                var value = zero
                for i in 0..<3 { try a.consumeWork(1); value = try f.adding(value,f.multiplying(x[i],y[i],using:&a),using:&a) }
                return value
            }
            guard try f.compare(dot(cross,cross,&a),f.multiplying(firstLength,firstLength,using:&a),using:&a) == .equal,
                try f.compare(dot(n,n,&a),f.multiplying(normalLength,normalLength,using:&a),using:&a) == .equal else { throw OriginalSourceIssuanceFailure.invalidChart }
            let u = try f.dividing(cross,by:firstLength,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:F.Value.self))
            let vRaw = [try f.subtracting(f.multiplying(n[1],u[2],using:&a),f.multiplying(n[2],u[1],using:&a),using:&a),
                try f.subtracting(f.multiplying(n[2],u[0],using:&a),f.multiplying(n[0],u[2],using:&a),using:&a),
                try f.subtracting(f.multiplying(n[0],u[1],using:&a),f.multiplying(n[1],u[0],using:&a),using:&a)]
            let v = try f.dividing(vRaw,by:normalLength,using:&a)
            let one = try f.integer(1,using:&a)
            guard try f.sign(of:dot(n,u,&a),using:&a) == .zero,try f.sign(of:dot(n,v,&a),using:&a) == .zero,
                try f.sign(of:dot(u,v,&a),using:&a) == .zero,try f.compare(dot(u,u,&a),one,using:&a) == .equal,
                try f.compare(dot(v,v,&a),one,using:&a) == .equal else { throw OriginalSourceIssuanceFailure.invalidChart }
            let result = OriginalPlaneBasisReceipt(source:copy source,field:f,origin:origin,normal:n,u:u,v:v)
            try a.checkpoint(); return result
        } catch { throw .init(preserving:error) }
    }
}
