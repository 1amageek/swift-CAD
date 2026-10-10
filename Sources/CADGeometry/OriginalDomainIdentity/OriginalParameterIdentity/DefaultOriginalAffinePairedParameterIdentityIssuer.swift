#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct DefaultOriginalAffinePairedParameterIdentityIssuer<S: Sendable,L: OriginalChartFamilyQuerying,R: OriginalChartFamilyQuerying>: OriginalAffinePairedParameterIdentityIssuing where L.Source == R.Source, L.Field == R.Field {
    public typealias Source = S
    public typealias LeftFamily = L
    public typealias RightFamily = R
    typealias F = L.Field
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
        _ identity: borrowing OriginalParameterIdentity<L.Source,L.Field>,
        from left: borrowing OriginalAffineChildDomainCover<S,L>,
        to right: borrowing OriginalAffineChildDomainCover<S,R>,
        leftAction: borrowing OriginalSourceAffineActionReceipt<S,L.Field>,
        rightAction: borrowing OriginalSourceAffineActionReceipt<S,L.Field>,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,L.Field> {
        try compose(identity,left:copy left,right:copy right,leftAction:copy leftAction,rightAction:copy rightAction,
            sharedCover:false,limits:limits,using:&admission)
    }

    // The single-cover entry supplies the identical retained cover to both sides.
    func compose<A: ExactScalarAdmission & ~Copyable>(
        _ identity: borrowing OriginalParameterIdentity<L.Source,L.Field>,
        left: OriginalAffineChildDomainCover<S,L>,right: OriginalAffineChildDomainCover<S,R>,
        leftAction: OriginalSourceAffineActionReceipt<S,F>?,rightAction: OriginalSourceAffineActionReceipt<S,F>?,
        sharedCover: Bool,limits: OriginalDomainIdentityLimits,using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let child = copy identity
        return try OriginalDomainAccess.run(&admission) { a in
            let transporter = DefaultOriginalParameterTransporter<S,F>()
            try transporter.admitted(left.correspondence,limits:limits,using:&a)
            try transporter.admitted(left.reverse,limits:limits,using:&a)
            guard left.templateCount <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            guard left.integerFamilyRank <= limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
            if !sharedCover {
                try transporter.admitted(right.correspondence,limits:limits,using:&a)
                try transporter.admitted(right.reverse,limits:limits,using:&a)
                guard right.templateCount <= limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
                guard right.integerFamilyRank <= limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
            }
            guard child.left.sharesFrame(with:left.childFamily.support),
                child.right.sharesFrame(with:right.childFamily.support) else { throw OriginalDomainIdentityFailure.foreignOwner }
            if let leftAction,let rightAction {
                guard leftAction.source.owns(left.support.frame.owner.anchor),
                    rightAction.source.owns(right.support.frame.owner.anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
                try leftAction.admitProof(limits:limits.source,using:&a)
                try rightAction.admitProof(limits:limits.source,using:&a)
                let field = right.support.frame.scalarField
                for row in 0..<3 { for column in 0..<4 {
                    try a.consumeWork(1)
                    let x = try leftAction.action.coefficient(row:row,column:column,using:&a)
                    let y = try rightAction.action.coefficient(row:row,column:column,using:&a)
                    // FIXME(INCOMPLETE_IMPLEMENTATION): This public paired transport proves equal
                    // original affine actions only. Unequal actions need a separate whole-scope
                    // source theorem before their boundary identity can be published.
                    guard try field.compare(x,y,using:&a) == .equal else { throw OriginalDomainIdentityFailure.unsupportedSourceProof }
                } }
            } else {
                guard sharedCover,leftAction == nil,rightAction == nil,
                    left.support.sharesFrame(with:right.support) else { throw OriginalDomainIdentityFailure.foreignOwner }
            }
            let childIssuer = DefaultOriginalParameterIdentityIssuer<L.Source,F>()
            let selectedLeft = try rebase(left.correspondence.local,to:left.childFamily.support.frame,limits:limits,&a)
            let selectedRight = sharedCover ? selectedLeft : try rebase(right.correspondence.local,to:right.childFamily.support.frame,limits:limits,&a)
            let restricted = try childIssuer.restricted(child,left:selectedLeft,right:selectedRight,limits:limits,using:&a)
            let leftLocal = try rebase(restricted.left,to:left.correspondence.local.frame,limits:limits,&a)
            let rightLocal = try rebase(restricted.right,to:right.correspondence.local.frame,limits:limits,&a)
            let selectedParentLeft = try transporter.restrict(left.correspondence,to:leftLocal,limits:limits,using:&a).image
            let selectedParentRight = try transporter.restrict(right.correspondence,to:rightLocal,limits:limits,using:&a).image
            let depth = try OriginalDomainAccess.add(max(child.depth,max(left.correspondence.depth,right.correspondence.depth)),1)
            let count = try OriginalDomainAccess.add(child.proofCount,1)
            guard depth <= limits.maximumTransportDepth else { throw OriginalDomainIdentityFailure.transportDepthLimit }
            guard count <= limits.maximumIdentityProofs else { throw OriginalDomainIdentityFailure.identityLimit }
            let f = selectedParentRight.frame.scalarField, map = left.correspondence, target = right.correspondence, n = selectedParentLeft.arity
            var permutation: [Int]?, gains: [F.Value] = [], offsets: [F.Value] = []
            if let q = restricted.permutation {
                try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),Int.self,&a)
                try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,2),F.Value.self,&a)
                var inverse = [Int](repeating:0,count:n), output: [Int] = []
                output.reserveCapacity(n); gains.reserveCapacity(n); offsets.reserveCapacity(n)
                for i in 0..<n { try a.consumeWork(1); inverse[map.permutation[i]] = i }
                for i in 0..<n {
                    try a.consumeWork(1)
                    let j = target.permutation[i], k = inverse[q[j]]
                    output.append(k)
                    let ratio = try f.dividing(restricted.gains[j],map.gains[k],using:&a)
                    gains.append(try f.multiplying(target.gains[i],ratio,using:&a))
                    offsets.append(try f.adding(f.multiplying(target.gains[i],
                        f.subtracting(restricted.offsets[j],f.multiplying(ratio,map.offsets[k],using:&a),using:&a),using:&a),target.offsets[i],using:&a))
                }
                permutation = output
            }
            typealias Readmission = OriginalIdentityReadmission<F>
            let childOwner = try Readmission.preserving(child,using:&a)
            try OriginalDomainAccess.storage(try OriginalDomainAccess.multiplied(n,sharedCover ? 4:8),Readmission.Scalar.self,&a)
            var scalars: [Readmission.Scalar] = []; scalars.reserveCapacity(try OriginalDomainAccess.multiplied(n,sharedCover ? 4:8))
            func retainWord(_ word: OriginalParameterTransport<S,F>,_ a: inout A) throws {
                for i in word.gains.indices {
                    try a.consumeWork(2)
                    scalars.append(.init(field:word.image.frame.scalarField,value:word.gains[i]))
                    scalars.append(.init(field:word.image.frame.scalarField,value:word.offsets[i]))
                }
            }
            try retainWord(map,&a); try retainWord(left.reverse,&a)
            if !sharedCover { try retainWord(target,&a);try retainWord(right.reverse,&a) }
            try OriginalDomainAccess.storage(1,Readmission.self,&a)
            let evidence: any Sendable
            var actions: [OriginalSourceAffineAction<F>] = []
            if let leftAction,let rightAction {
                try OriginalDomainAccess.storage(2,OriginalSourceAffineAction<F>.self,&a)
                actions = [leftAction.action,rightAction.action]
                try OriginalDomainAccess.owner((OriginalAffineChildDomainCover<S,L>,OriginalAffineChildDomainCover<S,R>,OriginalParameterIdentity<L.Source,F>,OriginalSourceAffineActionReceipt<S,F>,OriginalSourceAffineActionReceipt<S,F>).self,&a)
                evidence = OriginalAffinePairedIdentityEvidence(left:left,right:right,child:child,leftAction:leftAction,rightAction:rightAction)
            } else {
                try OriginalDomainAccess.owner((OriginalAffineChildDomainCover<S,L>,OriginalParameterIdentity<L.Source,F>).self,&a)
                evidence = OriginalAffineChildIdentityEvidence(cover:left,child:child)
            }
            try OriginalDomainAccess.storage(1,(any Sendable).self,&a)
            try OriginalDomainAccess.owner(([Readmission.Scalar],[Readmission],[any Sendable],ExactScalarDepth?,[OriginalSourceAffineAction<F>]).self,&a)
            let inherited = Readmission(scalars:scalars,parents:[childOwner],retained:[evidence],actions:actions)
            try OriginalDomainAccess.storage(2,OriginalSourceBinding<S>.self,&a)
            try OriginalDomainAccess.owner(([OriginalSourceBinding<S>],[ExactPolynomial<F>],[OriginalSourcePeriodReceipt<S,F>],[OriginalSourceBoundaryDeclaration<S>],[OriginalSourcePoleReceipt<S,F>],[OriginalSourceCollapsedFiberReceipt<S,F>],[OriginalParameterIdentity<S,F>],Readmission?).self,&a)
            let proof = OriginalParameterIdentity<S,F>.Proof(sources:[selectedParentLeft.frame.source,selectedParentRight.frame.source],laws:[],periods:[],boundaries:[],poles:[],fibers:[],parents:[],inherited:inherited)
            var valueDepth = child.evidenceDepth.value, coefficientDepth = child.evidenceDepth.coefficient
            func retainDepth<T: Sendable>(_ selection: OriginalParameterSelection<T,F>,_ a: inout A) throws {
                for axis in selection.axes { try a.consumeWork(1); valueDepth = max(valueDepth,axis.depth.value); coefficientDepth = max(coefficientDepth,axis.depth.coefficient) }
            }
            try retainDepth(child.left,&a); try retainDepth(child.right,&a)
            try retainDepth(map.local,&a); try retainDepth(map.image,&a)
            try retainDepth(left.reverse.local,&a); try retainDepth(left.reverse.image,&a)
            if !sharedCover {
                try retainDepth(target.local,&a);try retainDepth(target.image,&a)
                try retainDepth(right.reverse.local,&a);try retainDepth(right.reverse.image,&a)
            }
            for action in actions {
                try a.consumeWork(1)
                valueDepth = max(valueDepth,action.evidenceDepth.value)
                coefficientDepth = max(coefficientDepth,action.evidenceDepth.coefficient)
            }
            try retainDepth(selectedParentLeft,&a); try retainDepth(selectedParentRight,&a)
            let result = OriginalParameterIdentity(kind:child.kind,left:selectedParentLeft,right:selectedParentRight,permutation:permutation,gains:gains,offsets:offsets,
                depth:depth,proofCount:count,evidenceDepth:try .init(value:valueDepth,coefficient:coefficientDepth),
                evidenceSourceDepth:max(child.evidenceSourceDepth,max(left.source.sourceDepth,right.source.sourceDepth)),proof:proof)
            try DefaultOriginalParameterIdentityIssuer<S,F>().require(result,limits,&a)
            return result
        }
    }
}
