#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalParameterTransporter<Source: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering>: OriginalParameterTransporting {
    public typealias Field = F
    public init() {}
    public func frame<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<Source>, field: F,
        support: borrowing [[ExactParameterInterval<F.Value>]], semantics: [OriginalCoordinateSemantics],
        limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<Source,F> {
        let input = copy support; let binding = copy source
        return try OriginalDomainAccess.run(&admission) { a in
            guard input.count == semantics.count else { throw OriginalDomainIdentityFailure.invalidDomain }
            guard binding.sourceDepth <= limits.source.remainingSourceDepth else { throw OriginalDomainIdentityFailure.sourceDepthLimit }
            try OriginalDomainAccess.storage(input.count,ExactParameterDomain<F>.self,&a)
            try OriginalDomainAccess.storage(input.count,ExactParameterSet<F>.self,&a)
            var domains: [ExactParameterDomain<F>] = []; var selected: [ExactParameterSet<F>] = []
            domains.reserveCapacity(input.count); selected.reserveCapacity(input.count)
            let zero = try ExactScalarDepth(value:0,coefficient:0)
            for axis in input {
                try a.consumeWork(1)
                let domain = try ExactParameterDomain(field:field,depth:zero,using:&a)
                domains.append(domain); selected.append(try domain.set(intervals:axis,using:&a))
            }
            let anchor = try binding.chart(0,limits:limits.source,using:&a)
            try OriginalDomainAccess.owner((OriginalSourceChart<Source,Int>,F,[ExactParameterDomain<F>],[ExactParameterSet<F>],[OriginalCoordinateSemantics]).self,&a)
            return .init(owner:.init(anchor:anchor,field:field,domains:domains,support:selected,semantics:semantics))
        }
    }
    public func admitted<A: ExactScalarAdmission & ~Copyable>(_ map: borrowing OriginalParameterTransport<Source,F>,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) {
        let map = copy map
        try OriginalDomainAccess.run(&admission) { a in try require(map,limits,&a) }
    }
    public func reframed<A: ExactScalarAdmission & ~Copyable>(_ map: borrowing OriginalParameterTransport<Source,F>,
        to target: borrowing OriginalParameterFrame<Source,F>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterTransport<Source,F> {
        let map = copy map,target = copy target
        return try OriginalDomainAccess.run(&admission) { a in
            try require(map,limits,&a)
            return try affine(map.local,target,map.permutation,map.gains,map.offsets,depth:map.depth,limits:limits,using:&a)
        }
    }
    func require<A: ExactScalarAdmission & ~Copyable>(_ map: OriginalParameterTransport<Source,F>,
        _ limits: OriginalDomainIdentityLimits, _ a: inout A) throws {
        guard map.depth <= limits.maximumTransportDepth else { throw OriginalDomainIdentityFailure.transportDepthLimit }
        try map.local.frame.require(limits,&a); try map.image.frame.require(limits,&a)
        for axis in map.local.storage { try a.consumeWork(1); try a.admitDepth(value:axis.depth.value,coefficient:axis.depth.coefficient) }
        for axis in map.image.storage { try a.consumeWork(1); try a.admitDepth(value:axis.depth.value,coefficient:axis.depth.coefficient) }
        // Unbounded images have no finite endpoints to admit the retained word values.
        for i in map.gains.indices {
            try a.consumeWork(1)
            _ = try map.image.frame.scalarField.sign(of:map.gains[i],using:&a)
            _ = try map.image.frame.scalarField.sign(of:map.offsets[i],using:&a)
        }
    }
    func bound<A: ExactScalarAdmission & ~Copyable>(_ value: ExactParameterBound<F.Value>, gain: F.Value,
        offset: F.Value, sign: ExactSign, field: F, _ a: inout A) throws -> ExactParameterBound<F.Value> {
        try a.consumeWork(1)
        switch value {
        case .negativeInfinity: return sign == .positive ? .negativeInfinity : .positiveInfinity
        case .positiveInfinity: return sign == .positive ? .positiveInfinity : .negativeInfinity
        case .finite(let x): return .finite(try field.adding(field.multiplying(x,gain,using:&a),offset,using:&a))
        }
    }
    func image<A: ExactScalarAdmission & ~Copyable>(_ input: ExactParameterSet<F>, gain: F.Value, offset: F.Value,
        domain: ExactParameterDomain<F>, field: F, _ a: inout A) throws -> ExactParameterSet<F> {
        let sign = try field.sign(of:gain,using:&a)
        guard sign != .zero else { throw OriginalDomainIdentityFailure.singularTransport }
        _ = try field.sign(of:offset,using:&a)
        try OriginalDomainAccess.storage(input.intervalCount,ExactParameterInterval<F.Value>.self,&a)
        var output: [ExactParameterInterval<F.Value>] = []; output.reserveCapacity(input.intervalCount)
        for item in input.intervals {
            try a.consumeWork(1)
            let lo = try bound(item.lower,gain:gain,offset:offset,sign:sign,field:field,&a)
            let hi = try bound(item.upper,gain:gain,offset:offset,sign:sign,field:field,&a)
            output.append(try .checked(field:field,lower:sign == .positive ? lo : hi,upper:sign == .positive ? hi : lo,
                includesLower:sign == .positive ? item.includesLower : item.includesUpper,
                includesUpper:sign == .positive ? item.includesUpper : item.includesLower,depth:item.depth,using:&a))
        }
        return try domain.set(intervals:output,using:&a)
    }
    public func affine<A: ExactScalarAdmission & ~Copyable>(from local: borrowing OriginalParameterSelection<Source,F>,
        to authored: borrowing OriginalParameterFrame<Source,F>, permutation: [Int], gains: [F.Value], offsets: [F.Value],
        limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterTransport<Source,F> {
        try affine(copy local,copy authored,permutation,gains,offsets,depth:1,limits:limits,using:&admission)
    }
    func affine<A: ExactScalarAdmission & ~Copyable>(_ local: OriginalParameterSelection<Source,F>,
        _ authored: OriginalParameterFrame<Source,F>, _ permutation: [Int], _ gains: [F.Value], _ offsets: [F.Value],
        depth: Int, limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterTransport<Source,F> {
        try OriginalDomainAccess.run(&admission) { a in
            try local.frame.require(limits,&a); try authored.require(limits,&a)
            guard depth <= limits.maximumTransportDepth else { throw OriginalDomainIdentityFailure.transportDepthLimit }
            guard local.frame.source.owns(authored.owner.anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            // An invertible word requires both directions in the retained fields.
            // Merely matching values in unbounded supports cannot validate this.
            let localZero = try local.frame.owner.field.integer(0,using:&a)
            let authoredZero = try authored.owner.field.integer(0,using:&a)
            _ = try authored.owner.field.compare(localZero,authoredZero,using:&a)
            _ = try local.frame.owner.field.compare(authoredZero,localZero,using:&a)
            let n = local.arity
            guard authored.arity == n, permutation.count == n, gains.count == n, offsets.count == n else {
                throw OriginalDomainIdentityFailure.invalidDomain
            }
            try OriginalDomainAccess.storage(n,Bool.self,&a)
            var seen = [Bool](repeating:false,count:n)
            try OriginalDomainAccess.storage(n,ExactParameterSet<F>.self,&a)
            var axes: [ExactParameterSet<F>] = []; axes.reserveCapacity(n)
            for i in 0..<n {
                try a.consumeWork(1); let j = permutation[i]
                guard j >= 0, j < n, !seen[j] else { throw OriginalDomainIdentityFailure.invalidDomain }; seen[j] = true
                guard authored.owner.semantics[i] == local.frame.owner.semantics[j] else { throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics }
                guard try local.frame.owner.domains[j].difference(local.storage[j],local.frame.owner.support[j],using:&a).isEmpty else {
                    throw OriginalDomainIdentityFailure.outsideSupport
                }
                let transformed = try image(local.storage[j],gain:gains[i],offset:offsets[i],domain:authored.owner.domains[i],field:authored.owner.field,&a)
                guard try authored.owner.domains[i].difference(transformed,authored.owner.support[i],using:&a).isEmpty else {
                    throw OriginalDomainIdentityFailure.outsideSupport
                }
                axes.append(transformed)
            }
            return .init(local:local,image:try .init(frame:authored,axes:axes,using:&a),permutation:permutation,gains:gains,offsets:offsets,depth:depth)
        }
    }
    func contains<A: ExactScalarAdmission & ~Copyable>(_ tuple: [F.Value], _ selection: OriginalParameterSelection<Source,F>,
        _ a: inout A) throws -> Bool {
        guard tuple.count == selection.arity else { throw OriginalDomainIdentityFailure.invalidDomain }
        var included = true
        for i in tuple.indices {
            try a.consumeWork(1)
            if try !selection.frame.owner.domains[i].contains(tuple[i],in:selection.storage[i],using:&a) { included = false }
        }
        return included
    }
    public func forward<A: ExactScalarAdmission & ~Copyable>(_ tuple: borrowing [F.Value],
        through map: borrowing OriginalParameterTransport<Source,F>, limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [F.Value] {
        let input = copy tuple; let m = copy map
        return try OriginalDomainAccess.run(&admission) { a in
            try require(m,limits,&a)
            guard try contains(input,m.local,&a) else { throw OriginalDomainIdentityFailure.outsideSupport }
            try OriginalDomainAccess.storage(input.count,F.Value.self,&a)
            var output: [F.Value] = []; output.reserveCapacity(input.count)
            for i in input.indices {
                try a.consumeWork(1)
                output.append(try m.image.frame.owner.field.adding(m.image.frame.owner.field.multiplying(input[m.permutation[i]],m.gains[i],using:&a),m.offsets[i],using:&a))
            }
            return output
        }
    }
    public func inverse<A: ExactScalarAdmission & ~Copyable>(_ map: borrowing OriginalParameterTransport<Source,F>,
        limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterTransport<Source,F> {
        let m = copy map
        return try OriginalDomainAccess.run(&admission) { a in
            try require(m,limits,&a)
            let n = m.local.arity; let f = m.local.frame.owner.field
            try OriginalDomainAccess.storage(n,Int.self,&a); try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),F.Value.self,&a)
            let zero = try f.integer(0,using:&a), one = try f.integer(1,using:&a)
            var p = [Int](repeating:0,count:n), g = [F.Value](repeating:zero,count:n), o = g
            // The second coefficient buffer is separately admitted above; mutation triggers its COW copy.
            for i in 0..<n {
                try a.consumeWork(1); let j = m.permutation[i]; p[j] = i
                g[j] = try f.dividing(one,m.gains[i],using:&a)
                o[j] = try f.negated(f.dividing(m.offsets[i],m.gains[i],using:&a),using:&a)
            }
            return try affine(m.image,m.local.frame,p,g,o,depth:try OriginalDomainAccess.add(m.depth,1),limits:limits,using:&a)
        }
    }
    public func restrict<A: ExactScalarAdmission & ~Copyable>(_ map: borrowing OriginalParameterTransport<Source,F>,
        to selection: borrowing OriginalParameterSelection<Source,F>, limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterTransport<Source,F> {
        let m = copy map; let selected = copy selection
        return try OriginalDomainAccess.run(&admission) { a in
            try require(m,limits,&a)
            guard selected.frame.owner === m.local.frame.owner else { throw OriginalDomainIdentityFailure.foreignOwner }
            try OriginalDomainAccess.storage(m.local.arity,ExactParameterSet<F>.self,&a)
            var axes: [ExactParameterSet<F>] = []; axes.reserveCapacity(m.local.arity)
            for i in 0..<m.local.arity { try a.consumeWork(1); axes.append(try m.local.frame.owner.domains[i].intersection(m.local.storage[i],selected.storage[i],using:&a)) }
            return try affine(.init(frame:m.local.frame,axes:axes,using:&a),m.image.frame,m.permutation,m.gains,m.offsets,
                depth:m.depth,limits:limits,using:&a)
        }
    }
    public func compose<A: ExactScalarAdmission & ~Copyable>(_ first: borrowing OriginalParameterTransport<Source,F>,
        _ second: borrowing OriginalParameterTransport<Source,F>, limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterTransport<Source,F> {
        let l = copy first; let r = copy second
        return try OriginalDomainAccess.run(&admission) { a in
            try require(l,limits,&a); try require(r,limits,&a)
            guard l.image.frame.owner === r.local.frame.owner else { throw OriginalDomainIdentityFailure.foreignOwner }
            let n = l.local.arity; let f = l.local.frame.owner.field
            let reverse = try inverse(l,limits:limits,using:&a)
            let restrictedMiddle = try restrict(reverse,to:r.local,limits:limits,using:&a)
            let support = restrictedMiddle.image
            try OriginalDomainAccess.storage(n,Int.self,&a); try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),F.Value.self,&a)
            var p: [Int] = []; var g: [F.Value] = []; var o: [F.Value] = []
            p.reserveCapacity(n); g.reserveCapacity(n); o.reserveCapacity(n)
            for i in 0..<n {
                try a.consumeWork(1); let j = r.permutation[i]
                p.append(l.permutation[j]); g.append(try f.multiplying(l.gains[j],r.gains[i],using:&a))
                o.append(try f.adding(f.multiplying(l.offsets[j],r.gains[i],using:&a),r.offsets[i],using:&a))
            }
            return try affine(support,r.image.frame,p,g,o,depth:try OriginalDomainAccess.add(max(l.depth,r.depth),1),limits:limits,using:&a)
        }
    }
}
