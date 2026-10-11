#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Reduces only the proved axis section of the actual intrinsic Rodrigues law.
public struct DefaultOriginalRevolutionAxisSectionIssuer<S: OriginalRevolutionSourceReading,C: Sendable,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,L: OriginalLinearSourceReading>: OriginalRevolutionAxisSectionIssuing where F.Source == F.Value {
    public typealias Source=S
    public typealias GeneratorSelection=C
    public typealias Field=F
    public typealias Line=L
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(family: borrowing OriginalFiniteRevolutionLawFamily<S,C,F>,
        line: borrowing OriginalSourceBinding<L>,limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalRevolutionAxisSectionReceipt<S,C,F,L> {
        let family=copy family,line=copy line
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
                try a.checkpoint();try family.admitProof(limits:limits,using:&a);try line.require(limits)
                let f=family.field,zero=try f.integer(0,using:&a)
                let lineLaw=try DefaultOriginalWholeLinearLawIssuer<L,F>().issue(source:line,field:f,limits:limits,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:9,of:F.Value.self))
                var origin:[F.Value]=[],axis:[F.Value]=[],delta:[F.Value]=[]
                origin.reserveCapacity(3);axis.reserveCapacity(3);delta.reserveCapacity(3)
                var axisNorm=zero,lineNorm=zero
                for i in 0..<3 {
                    try a.consumeWork(1)
                    let o=try f.binary64(exactly:family.source.original.axisOriginCoordinate(in:i),using:&a)
                    let d=try f.binary64(exactly:family.source.original.axisDirectionCoordinate(in:i),using:&a)
                    origin.append(o);axis.append(d);delta.append(try f.subtracting(lineLaw.origin[i],o,using:&a))
                    axisNorm=try f.adding(axisNorm,f.multiplying(d,d,using:&a),using:&a)
                    lineNorm=try f.adding(lineNorm,f.multiplying(lineLaw.direction[i],lineLaw.direction[i],using:&a),using:&a)
                }
                guard try f.sign(of:axisNorm,using:&a) == .positive,
                    try f.sign(of:lineNorm,using:&a) == .positive else { throw OriginalSourceIssuanceFailure.invalidSource }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:6,of:F.Value.self))
                var lineResiduals:[F.Value]=[];lineResiduals.reserveCapacity(6)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:[F.Value].self))
                for vector in [lineLaw.direction,delta] {
                    for i in 0..<3 {
                        let j=(i+1)%3,k=(i+2)%3
                        let residual=try f.subtracting(f.multiplying(vector[j],axis[k],using:&a),f.multiplying(vector[k],axis[j],using:&a),using:&a)
                        guard try f.sign(of:residual,using:&a) == .zero else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                        lineResiduals.append(residual)
                    }
                }
                typealias Graph=OriginalParametricGraphReceipt<S,F,OriginalRevolutionAxisSectionEvidence<S,C,F,L>>
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:family.laws.count,of:Graph.self))
                var graphs:[Graph]=[];graphs.reserveCapacity(family.laws.count)
                for law in family.laws {
                    try a.consumeWork(1)
                    guard law.source.owner === family.source.owner else { throw OriginalSourceIssuanceFailure.foreignBinding }
                    _ = try f.importing(law.field.integer(0,using:&a),using:&a)
                    graphs.append(try graph(law:law,line:lineLaw,origin:origin,axis:axis,axisNorm:axisNorm,lineNorm:lineNorm,
                        lineResiduals:lineResiduals,limits:limits,using:&a))
                }
                let depth=try a.depth
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalRevolutionAxisSectionReceipt<S,C,F,L>.self))
                let result=OriginalRevolutionAxisSectionReceipt(family:family,line:line,graphs:graphs,proofDepth:depth)
                try a.checkpoint();return result
            }
        } catch { throw .init(preserving:error) }
    }

    private func graph<A: ExactScalarAdmission & ~Copyable>(law: OriginalRevolutionLawReceipt<S,C,F>,
        line: OriginalWholeLinearLawReceipt<L,F>,origin:[F.Value],axis:[F.Value],axisNorm:F.Value,lineNorm:F.Value,
        lineResiduals:[F.Value],limits:OriginalSourceIssuanceLimits,using a:inout OriginalSourceProofAdmission<A>)
        throws -> OriginalParametricGraphReceipt<S,F,OriginalRevolutionAxisSectionEvidence<S,C,F,L>> {
        try law.admitProof(limits:limits,using:&a)
        let ring=law.polynomials,f=law.field
        guard ring.variableCount == 3,law.homogeneous.count == 4,law.support.count == 2 else { throw OriginalSourceIssuanceFailure.invalidChart }
        let zero=try ring.constant(f.integer(0,using:&a),using:&a),cos=try ring.variable(0,using:&a),sin=try ring.variable(1,using:&a)
        let v=try ring.variable(2,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:ExactPolynomial<F>.self))
        let projection=[zero,zero,v]
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:10,of:ExactPolynomial<F>.self))
        var base:[ExactPolynomial<F>]=[],radial:[ExactPolynomial<F>]=[],cross:[ExactPolynomial<F>]=[]
        base.reserveCapacity(4);radial.reserveCapacity(3);cross.reserveCapacity(3)
        for i in 0..<4 { base.append(try ring.substituted(law.homogeneous[i],with:projection,using:&a)) }
        for i in 0..<3 {
            radial.append(try ring.substituted(ring.differentiated(law.homogeneous[i],in:0,using:&a),with:projection,using:&a))
            cross.append(try ring.substituted(ring.differentiated(law.homogeneous[i],in:1,using:&a),with:projection,using:&a))
        }
        let rho=try ring.substituted(law.radialSquaredNumerator,with:projection,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:13,of:ExactPolynomial<F>.self))
        var residuals:[ExactPolynomial<F>]=[];residuals.reserveCapacity(13)
        func check(_ residual:ExactPolynomial<F>,_ a:inout OriginalSourceProofAdmission<A>) throws {
            guard try ring.isZero(residual,using:&a) else { throw OriginalSourceIssuanceFailure.invalidChart }
            residuals.append(residual)
        }
        for i in 0..<3 {
            let reconstructed=try ring.adding(base[i],ring.adding(ring.multiplying(radial[i],cos,using:&a),ring.multiplying(cross[i],sin,using:&a),using:&a),using:&a)
            try check(ring.subtracting(law.homogeneous[i],reconstructed,using:&a),&a)
        }
        try check(ring.subtracting(law.denominator,base[3],using:&a),&a)
        try check(ring.subtracting(law.radialSquaredNumerator,rho,using:&a),&a)
        for i in 0..<3 {
            let j=(i+1)%3,k=(i+2)%3
            let rj=try ring.subtracting(base[j],ring.scaled(base[3],by:origin[j],using:&a),using:&a)
            let rk=try ring.subtracting(base[k],ring.scaled(base[3],by:origin[k],using:&a),using:&a)
            try check(ring.subtracting(ring.scaled(rj,by:axis[k],using:&a),ring.scaled(rk,by:axis[j],using:&a),using:&a),&a)
        }
        var radialDot=zero,crossDot=zero,mixed=zero,radialNorm=zero,crossNorm=zero
        for i in 0..<3 {
            radialDot=try ring.adding(radialDot,ring.scaled(radial[i],by:axis[i],using:&a),using:&a)
            crossDot=try ring.adding(crossDot,ring.scaled(cross[i],by:axis[i],using:&a),using:&a)
            mixed=try ring.adding(mixed,ring.multiplying(radial[i],cross[i],using:&a),using:&a)
            radialNorm=try ring.adding(radialNorm,ring.multiplying(radial[i],radial[i],using:&a),using:&a)
            crossNorm=try ring.adding(crossNorm,ring.multiplying(cross[i],cross[i],using:&a),using:&a)
        }
        try check(radialDot,&a);try check(crossDot,&a);try check(mixed,&a)
        try check(ring.subtracting(radialNorm,rho,using:&a),&a)
        try check(ring.subtracting(crossNorm,rho,using:&a),&a)
        // Defined intrinsic cosine/sine satisfy c*c+s*s=1. These whole identities
        // prove radial norm preservation; rho=0 forces both sum-of-squares vectors
        // to zero, and rho!=0 cannot meet the axis under the retained W!=0 guard.
        let parameters=try ExactPolynomialDomain(field:f,variableCount:2,using:&a)
        func reexpress(_ polynomial:ExactPolynomial<F>,_ a:inout OriginalSourceProofAdmission<A>) throws -> ExactPolynomial<F> {
            try a.admitDepth(value:polynomial.depth.value,coefficient:polynomial.depth.coefficient)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:polynomial.termCount,of:ExactPolynomialTerm<F.Value>.self))
            var terms:[ExactPolynomialTerm<F.Value>]=[];terms.reserveCapacity(polynomial.termCount)
            for term in polynomial.terms {
                try a.consumeWork(1)
                guard term.powers.count == 3,term.powers[0] == 0,term.powers[1] == 0 else { throw OriginalSourceIssuanceFailure.invalidChart }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Int.self))
                terms.append(.init(powers:[0,term.powers[2]],coefficient:try f.importing(term.coefficient,using:&a)))
            }
            return try parameters.polynomial(terms:terms,using:&a)
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<F>.self))
        var homogeneous:[ExactPolynomial<F>]=[];homogeneous.reserveCapacity(4)
        for polynomial in base { homogeneous.append(try reexpress(polynomial,&a)) }
        let radialGuard=try reexpress(rho,&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:OriginalParametricGraphCondition<F>.self))
        let conditions:[OriginalParametricGraphCondition<F>]=[.init(radialGuard,.equal),.init(homogeneous[3],.notEqual)]
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Int.self))
        let layout=try OriginalParametricVariableLayout.checked(variableCount:2,parameters:[0,1],auxiliaries:[],using:&a)
        let u=try parameters.variable(0,using:&a),parameterV=try parameters.variable(1,using:&a)
        let unit=try parameters.constant(f.integer(1,using:&a),using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<F>.self))
        let transport=OriginalRationalParameterTransport(numerators:[u,parameterV],denominators:[unit,unit])
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Bool.self))
        let sides=[true,true]
        let depth=try a.depth
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalRevolutionAxisSectionEvidence<S,C,F,L>.self))
        let evidence=OriginalRevolutionAxisSectionEvidence(law:law,line:line,axisOrigin:origin,axisDirection:axis,
            axisNormSquared:axisNorm,lineNormSquared:lineNorm,lineAxisResiduals:lineResiduals,identityResiduals:residuals,proofDepth:depth)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalParametricGraphReceipt<S,F,OriginalRevolutionAxisSectionEvidence<S,C,F,L>>.self))
        let result=OriginalParametricGraphReceipt(source:law.source,evidence:evidence,field:f,polynomials:parameters,
            homogeneous:homogeneous,support:law.support,includesUpperBoundary:sides,layout:layout,
            conditions:conditions,parameterTransport:transport,proofDepth:depth)
        try a.checkpoint();return result
    }
}
