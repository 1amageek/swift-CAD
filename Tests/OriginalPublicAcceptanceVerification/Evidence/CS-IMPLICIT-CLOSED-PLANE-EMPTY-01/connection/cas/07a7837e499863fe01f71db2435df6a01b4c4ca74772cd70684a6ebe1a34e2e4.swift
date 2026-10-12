#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalParameterIdentityIssuer<S: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering>: OriginalParameterIdentityIssuing, OriginalParameterIdentityQuerying {
    public typealias Source = S
    public typealias Field = F
    public init() {}
    func require<A: ExactScalarAdmission & ~Copyable>(_ r: OriginalParameterIdentity<S,F>,_ l: OriginalDomainIdentityLimits,_ a: inout A) throws {
        try r.left.frame.require(l,&a); try r.right.frame.require(l,&a)
        guard r.evidenceSourceDepth <= l.source.remainingSourceDepth else { throw OriginalDomainIdentityFailure.sourceDepthLimit }
        guard r.depth <= l.maximumTransportDepth else { throw OriginalDomainIdentityFailure.transportDepthLimit }
        guard r.proofCount <= l.maximumIdentityProofs else { throw OriginalDomainIdentityFailure.identityLimit }
        for axis in r.left.axes { try a.consumeWork(1); try a.admitDepth(value:axis.depth.value,coefficient:axis.depth.coefficient) }
        for axis in r.right.axes { try a.consumeWork(1); try a.admitDepth(value:axis.depth.value,coefficient:axis.depth.coefficient) }
        try a.admitDepth(value:r.evidenceDepth.value,coefficient:r.evidenceDepth.coefficient)
        for law in r.proof.laws { try a.consumeWork(1); try a.admitDepth(value:law.depth.value,coefficient:law.depth.coefficient) }
        for i in r.gains.indices {
            try a.consumeWork(1)
            _ = try r.right.frame.scalarField.sign(of:r.gains[i],using:&a)
            _ = try r.right.frame.scalarField.sign(of:r.offsets[i],using:&a)
        }
        for period in r.proof.periods {
            try a.consumeWork(1)
            _ = try period.field.sign(of:period.period,using:&a)
            _ = try period.field.sign(of:period.lower,using:&a)
            _ = try period.field.sign(of:period.upper,using:&a)
        }
        for pole in r.proof.poles {
            try a.consumeWork(1); _ = try pole.field.sign(of:pole.latitude,using:&a)
            for coordinate in pole.position { try a.consumeWork(1); _ = try pole.field.sign(of:coordinate,using:&a) }
        }
    }
    func make<A: ExactScalarAdmission & ~Copyable>(kind: OriginalParameterIdentityKind,left: OriginalParameterSelection<S,F>,right: OriginalParameterSelection<S,F>,
        permutation: [Int]?,gains: [F.Value],offsets: [F.Value],laws: [ExactPolynomial<F>] = [],periods: [OriginalSourcePeriodReceipt<S,F>] = [],
        boundaries: [OriginalSourceBoundaryDeclaration<S>] = [],poles: [OriginalSourcePoleReceipt<S,F>] = [],parents: [OriginalParameterIdentity<S,F>] = [],depth: Int = 1,using a: inout A,limits l: OriginalDomainIdentityLimits) throws -> OriginalParameterIdentity<S,F> {
        var count = 1
        var valueDepth = 0, coefficientDepth = 0
        var sourceDepth = max(left.frame.source.sourceDepth,right.frame.source.sourceDepth)
        for law in laws { try a.consumeWork(1); valueDepth = max(valueDepth,law.depth.value); coefficientDepth = max(coefficientDepth,law.depth.coefficient) }
        for parent in parents { try a.consumeWork(1); try require(parent,l,&a); count = try OriginalDomainAccess.add(count,parent.proofCount); sourceDepth = max(sourceDepth,parent.evidenceSourceDepth); valueDepth = max(valueDepth,parent.evidenceDepth.value); coefficientDepth = max(coefficientDepth,parent.evidenceDepth.coefficient) }
        guard count <= l.maximumIdentityProofs else { throw OriginalDomainIdentityFailure.identityLimit }
        guard depth <= l.maximumTransportDepth else { throw OriginalDomainIdentityFailure.transportDepthLimit }
        try OriginalDomainAccess.storage(2,OriginalSourceBinding<S>.self,&a)
        try OriginalDomainAccess.owner(([OriginalSourceBinding<S>],[ExactPolynomial<F>],[OriginalSourcePeriodReceipt<S,F>],[OriginalSourceBoundaryDeclaration<S>],[OriginalSourcePoleReceipt<S,F>],[OriginalParameterIdentity<S,F>]).self,&a)
        let proof = OriginalParameterIdentity<S,F>.Proof(sources:[left.frame.source,right.frame.source],laws:laws,periods:periods,boundaries:boundaries,poles:poles,parents:parents)
        let r = OriginalParameterIdentity(kind:kind,left:left,right:right,permutation:permutation,gains:gains,offsets:offsets,depth:depth,proofCount:count,evidenceDepth:try .init(value:valueDepth,coefficient:coefficientDepth),evidenceSourceDepth:sourceDepth,proof:proof)
        try require(r,l,&a); return r
    }
    public func authored<A: ExactScalarAdmission & ~Copyable>(left: borrowing OriginalParameterTransport<S,F>,right: borrowing OriginalParameterTransport<S,F>,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let left = copy left, right = copy right
        return try OriginalDomainAccess.run(&admission) { a in
            let t = DefaultOriginalParameterTransporter<S,F>()
            let inverse = try t.inverse(right,limits:limits,using:&a)
            let map = try t.compose(left,inverse,limits:limits,using:&a)
            return try make(kind:.authoredCoordinate,left:map.local,right:map.image,permutation:map.permutation,gains:map.gains,offsets:map.offsets,
                depth:map.depth,using:&a,limits:limits)
        }
    }
    public func decide<A: ExactScalarAdmission & ~Copyable>(_ receipt: borrowing OriginalParameterIdentity<S,F>,left: borrowing [F.Value],right: borrowing [F.Value],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentityDecision {
        let r = copy receipt, lhs = copy left, rhs = copy right
        return try OriginalDomainAccess.run(&admission) { a in
            try require(r,limits,&a)
            let includedL = try r.left.contains(lhs,limits:limits,using:&a)
            let includedR = try r.right.contains(rhs,limits:limits,using:&a)
            guard includedL && includedR else { return .notEstablished }
            guard let p = r.permutation else { return .proven }
            let f = r.right.frame.scalarField
            var same = true
            for i in p.indices {
                try a.consumeWork(1)
                let value = try f.adding(f.multiplying(lhs[p[i]],r.gains[i],using:&a),r.offsets[i],using:&a)
                if try f.compare(value,rhs[i],using:&a) != .equal { same = false }
            }
            return same ? .proven : .refutedForThisRelation
        }
    }
    func mapped<A: ExactScalarAdmission & ~Copyable>(_ selection: OriginalParameterSelection<S,F>,to frame: OriginalParameterFrame<S,F>,
        permutation p: [Int],gains: [F.Value],offsets: [F.Value],limits: OriginalDomainIdentityLimits,_ a: inout A) throws -> OriginalParameterSelection<S,F> {
        try selection.coordinateImage(to:frame,permutation:p,gains:gains,offsets:offsets,
            limits:limits,using:&a)
    }
    func inverted<A: ExactScalarAdmission & ~Copyable>(_ p: [Int],_ g: [F.Value],_ o: [F.Value],field f: F,_ a: inout A) throws -> ([Int],[F.Value],[F.Value]) {
        let n = p.count
        try OriginalDomainAccess.storage(n,Int.self,&a); try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),F.Value.self,&a)
        var permutation = [Int](repeating:0,count:n)
        let zero = try f.integer(0,using:&a), one = try f.integer(1,using:&a)
        var gains = [F.Value](repeating:zero,count:n), offsets = [F.Value](repeating:zero,count:n)
        for i in p.indices {
            try a.consumeWork(1); permutation[p[i]] = i
            gains[p[i]] = try f.dividing(one,g[i],using:&a)
            offsets[p[i]] = try f.negated(f.multiplying(o[i],gains[p[i]],using:&a),using:&a)
        }
        return (permutation,gains,offsets)
    }
    public func restricted<A: ExactScalarAdmission & ~Copyable>(_ receipt: borrowing OriginalParameterIdentity<S,F>,left: borrowing OriginalParameterSelection<S,F>,right: borrowing OriginalParameterSelection<S,F>,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let r = copy receipt, lhs = copy left, rhs = copy right
        return try OriginalDomainAccess.run(&admission) { a in
            try require(r,limits,&a)
            var l = try r.left.intersection(lhs,limits:limits,using:&a)
            var right = try r.right.intersection(rhs,limits:limits,using:&a)
            if let p = r.permutation {
                let (ip,ig,io) = try inverted(p,r.gains,r.offsets,field:l.frame.scalarField,&a)
                l = try l.intersection(mapped(right,to:l.frame,permutation:ip,gains:ig,offsets:io,limits:limits,&a),limits:limits,using:&a)
                right = try mapped(l,to:right.frame,permutation:p,gains:r.gains,offsets:r.offsets,limits:limits,&a)
            }
            // Restriction shares the original proof owner, and cannot add proof depth.
            return .init(kind:r.kind,left:l,right:right,permutation:r.permutation,gains:r.gains,offsets:r.offsets,depth:r.depth,proofCount:r.proofCount,evidenceDepth:r.evidenceDepth,evidenceSourceDepth:r.evidenceSourceDepth,proof:r.proof)
        }
    }
    public func symmetric<A: ExactScalarAdmission & ~Copyable>(_ receipt: borrowing OriginalParameterIdentity<S,F>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let r = copy receipt
        return try OriginalDomainAccess.run(&admission) { a in
            try require(r,limits,&a)
            if let p = r.permutation {
                let (ip,ig,io) = try inverted(p,r.gains,r.offsets,field:r.left.frame.scalarField,&a)
                return .init(kind:r.kind,left:r.right,right:r.left,permutation:ip,gains:ig,offsets:io,depth:r.depth,proofCount:r.proofCount,evidenceDepth:r.evidenceDepth,evidenceSourceDepth:r.evidenceSourceDepth,proof:r.proof)
            }
            return .init(kind:r.kind,left:r.right,right:r.left,permutation:nil,gains:[],offsets:[],depth:r.depth,proofCount:r.proofCount,evidenceDepth:r.evidenceDepth,evidenceSourceDepth:r.evidenceSourceDepth,proof:r.proof)
        }
    }
    public func compose<A: ExactScalarAdmission & ~Copyable>(_ first: borrowing OriginalParameterIdentity<S,F>,_ second: borrowing OriginalParameterIdentity<S,F>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let x = copy first, y = copy second
        return try OriginalDomainAccess.run(&admission) { a in
            try require(x,limits,&a); try require(y,limits,&a)
            guard x.kind == y.kind else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
            let middle = try x.right.intersection(y.left,limits:limits,using:&a)
            let depth = try OriginalDomainAccess.add(max(x.depth,y.depth),1)
            var left = x.left, right = y.right
            if let p = x.permutation {
                let (ip,ig,io) = try inverted(p,x.gains,x.offsets,field:left.frame.scalarField,&a)
                left = try left.intersection(mapped(middle,to:left.frame,permutation:ip,gains:ig,offsets:io,limits:limits,&a),limits:limits,using:&a)
            } else if middle.isEmpty { left = try left.intersection(mappedEmpty(left.frame,&a),limits:limits,using:&a) }
            if let p = y.permutation { right = try mapped(middle,to:right.frame,permutation:p,gains:y.gains,offsets:y.offsets,limits:limits,&a) }
            else if middle.isEmpty { right = try mappedEmpty(right.frame,&a) }
            var permutation: [Int]? = nil, gains: [F.Value] = [], offsets: [F.Value] = []
            if let p = x.permutation, let q = y.permutation {
                let n = q.count, f = right.frame.scalarField
                try OriginalDomainAccess.storage(n,Int.self,&a); try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),F.Value.self,&a)
                var output: [Int] = []; output.reserveCapacity(n)
                for i in q.indices {
                    try a.consumeWork(1); output.append(p[q[i]])
                    gains.append(try f.multiplying(y.gains[i],x.gains[q[i]],using:&a))
                    offsets.append(try f.adding(f.multiplying(y.gains[i],x.offsets[q[i]],using:&a),y.offsets[i],using:&a))
                }
                permutation = output
            }
            try OriginalDomainAccess.storage(2,OriginalParameterIdentity<S,F>.self,&a)
            return try make(kind:x.kind,left:left,right:right,permutation:permutation,gains:gains,offsets:offsets,
                parents:[x,y],depth:depth,using:&a,limits:limits)
        }
    }
    func mappedEmpty<A: ExactScalarAdmission & ~Copyable>(_ frame: OriginalParameterFrame<S,F>,_ a: inout A) throws -> OriginalParameterSelection<S,F> {
        try OriginalDomainAccess.storage(frame.arity,ExactParameterSet<F>.self,&a)
        var sets: [ExactParameterSet<F>] = []
        for d in frame.axisDomains { try a.consumeWork(1); sets.append(try d.empty(using:&a)) }
        return try .init(frame:frame,axes:sets,using:&a)
    }
}
