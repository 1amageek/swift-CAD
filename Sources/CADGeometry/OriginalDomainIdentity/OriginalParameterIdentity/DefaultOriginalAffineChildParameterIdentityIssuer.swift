#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalAffineChildParameterIdentityIssuer<S: Sendable,C: OriginalChartFamilyQuerying>: OriginalAffineChildParameterIdentityIssuing {
    public typealias Source = S
    public typealias ChildFamily = C
    typealias F = C.Field
    public init() {}

    // Coordinate rebasing is private and only follows the sealed cover's child authority.
    private func rebase<T: Sendable,U: Sendable,A: ExactScalarAdmission & ~Copyable>(
        _ selection: OriginalParameterSelection<T,F>, to frame: OriginalParameterFrame<U,F>,
        limits: OriginalDomainIdentityLimits, _ a: inout A
    ) throws -> OriginalParameterSelection<U,F> {
        guard selection.arity == frame.arity else { throw OriginalDomainIdentityFailure.invalidDomain }
        try OriginalDomainAccess.storage(frame.arity,[ExactParameterInterval<F.Value>].self,&a)
        var intervals: [[ExactParameterInterval<F.Value>]] = []; intervals.reserveCapacity(frame.arity)
        for axis in selection.axes {
            try a.consumeWork(1)
            try OriginalDomainAccess.storage(axis.intervalCount,ExactParameterInterval<F.Value>.self,&a)
            intervals.append(Array(axis.intervals))
        }
        return try frame.selection(intervals:intervals,limits:limits,using:&a)
    }

    public func lifted<A: ExactScalarAdmission & ~Copyable>(
        _ identity: borrowing OriginalParameterIdentity<C.Source,C.Field>,
        through cover: borrowing OriginalAffineChildDomainCover<S,C>,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,C.Field> {
        let child = copy identity, cover = copy cover
        return try OriginalDomainAccess.run(&admission) { a in
            let transporter = DefaultOriginalParameterTransporter<S,F>()
            try transporter.admitted(cover.correspondence,limits:limits,using:&a)
            try transporter.admitted(cover.reverse,limits:limits,using:&a)
            guard cover.templateCount <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            guard cover.integerFamilyRank <= limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
            guard child.left.sharesFrame(with:cover.childFamily.support),
                child.right.sharesFrame(with:cover.childFamily.support) else { throw OriginalDomainIdentityFailure.foreignOwner }
            let childIssuer = DefaultOriginalParameterIdentityIssuer<C.Source,F>()
            let selected = try rebase(cover.correspondence.local,to:cover.childFamily.support.frame,limits:limits,&a)
            let restricted = try childIssuer.restricted(child,left:selected,right:selected,limits:limits,using:&a)
            let leftLocal = try rebase(restricted.left,to:cover.correspondence.local.frame,limits:limits,&a)
            let rightLocal = try rebase(restricted.right,to:cover.correspondence.local.frame,limits:limits,&a)
            let left = try transporter.restrict(cover.correspondence,to:leftLocal,limits:limits,using:&a).image
            let right = try transporter.restrict(cover.correspondence,to:rightLocal,limits:limits,using:&a).image
            let depth = try OriginalDomainAccess.add(max(child.depth,cover.correspondence.depth),1)
            let count = try OriginalDomainAccess.add(child.proofCount,1)
            guard depth <= limits.maximumTransportDepth else { throw OriginalDomainIdentityFailure.transportDepthLimit }
            guard count <= limits.maximumIdentityProofs else { throw OriginalDomainIdentityFailure.identityLimit }
            let f = right.frame.scalarField, map = cover.correspondence, n = left.arity
            var permutation: [Int]?, gains: [F.Value] = [], offsets: [F.Value] = []
            if let q = restricted.permutation {
                try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),Int.self,&a)
                try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),F.Value.self,&a)
                var inverse = [Int](repeating:0,count:n), output: [Int] = []
                output.reserveCapacity(n); gains.reserveCapacity(n); offsets.reserveCapacity(n)
                for i in 0..<n { try a.consumeWork(1); inverse[map.permutation[i]] = i }
                for i in 0..<n {
                    try a.consumeWork(1)
                    let j = map.permutation[i], k = inverse[q[j]]
                    output.append(k)
                    let ratio = try f.dividing(restricted.gains[j],map.gains[k],using:&a)
                    gains.append(try f.multiplying(map.gains[i],ratio,using:&a))
                    offsets.append(try f.adding(f.multiplying(map.gains[i],
                        f.subtracting(restricted.offsets[j],f.multiplying(ratio,map.offsets[k],using:&a),using:&a),using:&a),map.offsets[i],using:&a))
                }
                permutation = output
            }
            typealias Readmission = OriginalIdentityReadmission<F>
            let childOwner = try Readmission.preserving(child,using:&a)
            try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,4),Readmission.Scalar.self,&a)
            var scalars: [Readmission.Scalar] = []; scalars.reserveCapacity(try OriginalDomainAccess.multiplied(n,4))
            func retainWord(_ word: OriginalParameterTransport<S,F>,_ a: inout A) throws {
                for i in word.gains.indices {
                    try a.consumeWork(2)
                    scalars.append(.init(field:word.image.frame.scalarField,value:word.gains[i]))
                    scalars.append(.init(field:word.image.frame.scalarField,value:word.offsets[i]))
                }
            }
            try retainWord(map,&a); try retainWord(cover.reverse,&a)
            try OriginalDomainAccess.storage(1,Readmission.self,&a)
            try OriginalDomainAccess.owner((OriginalAffineChildDomainCover<S,C>,OriginalParameterIdentity<C.Source,F>).self,&a)
            let evidence = OriginalAffineChildIdentityEvidence(cover:cover,child:child)
            try OriginalDomainAccess.storage(1,(any Sendable).self,&a)
            try OriginalDomainAccess.owner(([Readmission.Scalar],[Readmission],[any Sendable],ExactScalarDepth?).self,&a)
            let inherited = Readmission(scalars:scalars,parents:[childOwner],retained:[evidence])
            try OriginalDomainAccess.storage(2,OriginalSourceBinding<S>.self,&a)
            try OriginalDomainAccess.owner(([OriginalSourceBinding<S>],[ExactPolynomial<F>],[OriginalSourcePeriodReceipt<S,F>],[OriginalSourceBoundaryDeclaration<S>],[OriginalSourcePoleReceipt<S,F>],[OriginalSourceCollapsedFiberReceipt<S,F>],[OriginalParameterIdentity<S,F>],Readmission?).self,&a)
            let proof = OriginalParameterIdentity<S,F>.Proof(sources:[left.frame.source,right.frame.source],laws:[],periods:[],boundaries:[],poles:[],fibers:[],parents:[],inherited:inherited)
            var valueDepth = child.evidenceDepth.value, coefficientDepth = child.evidenceDepth.coefficient
            func retainDepth<T: Sendable>(_ selection: OriginalParameterSelection<T,F>,_ a: inout A) throws {
                for axis in selection.axes { try a.consumeWork(1); valueDepth = max(valueDepth,axis.depth.value); coefficientDepth = max(coefficientDepth,axis.depth.coefficient) }
            }
            try retainDepth(child.left,&a); try retainDepth(child.right,&a)
            try retainDepth(map.local,&a); try retainDepth(map.image,&a)
            try retainDepth(cover.reverse.local,&a); try retainDepth(cover.reverse.image,&a)
            try retainDepth(left,&a); try retainDepth(right,&a)
            let result = OriginalParameterIdentity(kind:child.kind,left:left,right:right,permutation:permutation,gains:gains,offsets:offsets,
                depth:depth,proofCount:count,evidenceDepth:try .init(value:valueDepth,coefficient:coefficientDepth),
                evidenceSourceDepth:max(cover.source.sourceDepth,child.evidenceSourceDepth),proof:proof)
            try DefaultOriginalParameterIdentityIssuer<S,F>().require(result,limits,&a)
            return result
        }
    }
}
