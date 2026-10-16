#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension DefaultOriginalParameterIdentityIssuer: OriginalLawBoundParameterIdentityIssuing where F: ExactScalarImporting {
    public func declaredBoundary<L: Sendable,R: Sendable,A: ExactScalarAdmission & ~Copyable>(
        declaration: borrowing OriginalRationalSourceBoundaryDeclaration<S,L,R,F>,
        scope: borrowing OriginalParameterSelection<S,F>,rightFrame: borrowing OriginalParameterFrame<S,F>,
        permutation: [Int],gains: [F.Value],offsets: [F.Value],
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<S,F> {
        let declaration = copy declaration,scope = copy scope,rightFrame = copy rightFrame
        return try OriginalDomainAccess.run(&admission) { a in
            try a.withProofScope { tracked in
                try lawBoundBoundary(declaration,scope:scope,rightFrame:rightFrame,
                    permutation:permutation,gains:gains,offsets:offsets,limits:limits,&tracked)
            }
        }
    }

    private func lawBoundCoordinates<C: Sendable,A: ExactScalarAdmission & ~Copyable>(
        _ law: OriginalRationalChartReceipt<S,C,F>,scope: OriginalParameterSelection<S,F>,
        laws: inout [ExactPolynomial<F>],limits: OriginalDomainIdentityLimits,_ a: inout A) throws {
        let ring = law.polynomials,f = law.field,n = scope.arity
        guard ring.variableCount == n,law.homogeneous.count == 4,
            law.parameterTransport.numerators.count == n,law.parameterTransport.denominators.count == n else {
            throw OriginalDomainIdentityFailure.invalidIdentityProof
        }
        try OriginalDomainAccess.storage(n,F.Value.self,&a)
        var anchor: [F.Value] = []; anchor.reserveCapacity(n)
        for axis in scope.axes {
            try a.consumeWork(1)
            guard let interval = axis.intervals.first,case .finite(let lo) = interval.lower,
                case .finite(let hi) = interval.upper else { throw OriginalDomainIdentityFailure.unsupportedSourceProof }
            anchor.append(try f.dividing(f.adding(lo,hi,using:&a),f.integer(2,using:&a),using:&a))
        }
        guard try scope.contains(anchor,queryField:f,limits:limits,using:&a) else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
        laws.append(contentsOf:law.homogeneous)
        laws.append(contentsOf:law.parameterTransport.numerators)
        laws.append(contentsOf:law.parameterTransport.denominators)
        for index in 0...n {
            try a.consumeWork(1)
            let guardLaw = index == n ? law.denominator : law.parameterTransport.denominators[index]
            let evaluated = try ring.evaluated(guardLaw,at:anchor,using:&a)
            try a.admitDepth(value:evaluated.depth.value,coefficient:evaluated.depth.coefficient)
            let constant = try ring.constant(evaluated.value,using:&a)
            let residual = try ring.subtracting(guardLaw,constant,using:&a)
            // FIXME(INCOMPLETE_IMPLEMENTATION): The law-bound declaredBoundary caller
            // currently proves only guards constant on its entire selected scope.
            // Nonconstant guards require complete nonzero-on-scope evidence before
            // this branch may authorize a positional identity or self exclusion.
            guard try zero(residual,on:scope,ring:ring,limits:limits,&a) else {
                throw OriginalDomainIdentityFailure.unsupportedSourceProof
            }
            guard try f.sign(of:evaluated.value,using:&a) != .zero else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
            laws.append(constant); laws.append(residual)
        }
        for axis in 0..<n {
            try a.consumeWork(1)
            let residual = try ring.subtracting(law.parameterTransport.numerators[axis],
                ring.multiplying(ring.variable(axis,using:&a),law.parameterTransport.denominators[axis],using:&a),using:&a)
            guard try zero(residual,on:scope,ring:ring,limits:limits,&a) else { throw OriginalDomainIdentityFailure.unsupportedSourceProof }
            laws.append(residual)
        }
    }

    private func lawBoundBoundary<L: Sendable,R: Sendable,A: ExactScalarAdmission & ~Copyable>(
        _ declaration: OriginalRationalSourceBoundaryDeclaration<S,L,R,F>,scope: OriginalParameterSelection<S,F>,
        rightFrame: OriginalParameterFrame<S,F>,permutation p: [Int],gains g: [F.Value],offsets o: [F.Value],
        limits: OriginalDomainIdentityLimits,_ a: inout A) throws -> OriginalParameterIdentity<S,F> {
        let left = declaration.left,right = declaration.right,n = scope.arity
        try left.admitProof(using:&a); try right.admitProof(using:&a)
        try validate(left,scope:scope,limits:limits,&a)
        guard declaration.leftAxis >= 0,declaration.leftAxis < left.support.count,
            declaration.rightAxis >= 0,declaration.rightAxis < right.support.count else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
        guard p.count == n,g.count == n,o.count == n,rightFrame.arity == n else { throw OriginalDomainIdentityFailure.invalidDomain }
        try OriginalDomainAccess.storage(n,Bool.self,&a)
        var seen = [Bool](repeating:false,count:n)
        for i in p.indices {
            try a.consumeWork(1)
            guard p[i] >= 0,p[i] < n,!seen[p[i]] else { throw OriginalDomainIdentityFailure.invalidDomain }
            seen[p[i]] = true
            guard scope.frame.coordinateSemantics[p[i]] == rightFrame.coordinateSemantics[i] else { throw OriginalDomainIdentityFailure.incompatibleCoordinateSemantics }
        }
        try boundarySide(scope,axis:declaration.leftAxis,
            value:declaration.leftSide == .lower ? left.support[declaration.leftAxis].lower : left.support[declaration.leftAxis].upper,&a)
        let target = try mapped(scope,to:rightFrame,permutation:p,gains:g,offsets:o,limits:limits,&a)
        try validate(right,scope:target,limits:limits,&a)
        try boundarySide(target,axis:declaration.rightAxis,
            value:declaration.rightSide == .lower ? right.support[declaration.rightAxis].lower : right.support[declaration.rightAxis].upper,&a)
        let proofCount = try OriginalDomainAccess.add(19,OriginalDomainAccess.multiplied(10,n))
        try OriginalDomainAccess.storage(proofCount,ExactPolynomial<F>.self,&a)
        var laws: [ExactPolynomial<F>] = []; laws.reserveCapacity(proofCount)
        try lawBoundCoordinates(left,scope:scope,laws:&laws,limits:limits,&a)
        try lawBoundCoordinates(right,scope:target,laws:&laws,limits:limits,&a)
        let ring = left.polynomials
        try OriginalDomainAccess.storage(n,ExactPolynomial<F>.self,&a)
        var substitutions: [ExactPolynomial<F>] = []; substitutions.reserveCapacity(n)
        for i in p.indices {
            try a.consumeWork(1)
            substitutions.append(try ring.adding(ring.scaled(ring.variable(p[i],using:&a),by:g[i],using:&a),ring.constant(o[i],using:&a),using:&a))
        }
        try OriginalDomainAccess.storage(4,ExactPolynomial<F>.self,&a)
        var substituted: [ExactPolynomial<F>] = []; substituted.reserveCapacity(4)
        for polynomial in right.homogeneous {
            try a.consumeWork(1)
            let imported = try ring.polynomial(terms:polynomial.terms,using:&a)
            substituted.append(try ring.substituted(imported,with:substitutions,using:&a))
        }
        laws.append(contentsOf:substituted)
        for axis in 0..<3 {
            try a.consumeWork(1)
            let residual = try ring.subtracting(ring.multiplying(left.homogeneous[axis],substituted[3],using:&a),
                ring.multiplying(substituted[axis],left.denominator,using:&a),using:&a)
            guard try zero(residual,on:scope,ring:ring,limits:limits,&a) else { throw OriginalDomainIdentityFailure.invalidIdentityProof }
            laws.append(residual)
        }
        let base = try make(kind:.declaredSharedBoundary,left:scope,right:target,permutation:p,gains:g,offsets:o,laws:laws,using:&a,limits:limits)
        let reached = try a.depth
        let depth = try ExactScalarDepth(value:max(base.evidenceDepth.value,reached.value),coefficient:max(base.evidenceDepth.coefficient,reached.coefficient))
        try OriginalDomainAccess.storage(1,(any Sendable).self,&a)
        try OriginalDomainAccess.owner(OriginalRationalSourceBoundaryDeclaration<S,L,R,F>.self,&a)
        try OriginalDomainAccess.owner(([OriginalIdentityReadmission<F>.Scalar],[OriginalIdentityReadmission<F>],[any Sendable],ExactScalarDepth?,[OriginalSourceAffineAction<F>]).self,&a)
        let inherited = OriginalIdentityReadmission<F>(scalars:[],parents:[],retained:[declaration],depth:depth)
        try OriginalDomainAccess.owner(([OriginalSourceBinding<S>],[ExactPolynomial<F>],[OriginalSourcePeriodReceipt<S,F>],[OriginalSourceBoundaryDeclaration<S>],[OriginalSourcePoleReceipt<S,F>],[OriginalSourceCollapsedFiberReceipt<S,F>],[OriginalParameterIdentity<S,F>],OriginalIdentityReadmission<F>?).self,&a)
        let original = base.proof
        let proof = OriginalParameterIdentity<S,F>.Proof(sources:original.sources,laws:original.laws,periods:original.periods,
            boundaries:original.boundaries,poles:original.poles,fibers:original.fibers,parents:original.parents,inherited:inherited)
        try OriginalDomainAccess.storage(1,OriginalParameterIdentity<S,F>.self,&a)
        let result = OriginalParameterIdentity(kind:base.kind,left:base.left,right:base.right,permutation:base.permutation,
            gains:base.gains,offsets:base.offsets,depth:base.depth,proofCount:base.proofCount,evidenceDepth:depth,
            evidenceSourceDepth:base.evidenceSourceDepth,proof:proof)
        try require(result,limits,&a); try a.checkpoint(); return result
    }
}
