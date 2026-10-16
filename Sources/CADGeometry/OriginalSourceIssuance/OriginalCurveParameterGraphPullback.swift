#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Relational pullback keeps all child witnesses instead of choosing an inverse.
enum OriginalCurveParameterGraphPullback {
    static func issue<S: Sendable,C: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,E: Sendable,A: ExactScalarAdmission & ~Copyable>(
        source: OriginalSourceBinding<S>,child: OriginalParametricGraphReceipt<C,F,E>,gain: F.Value,offset: F.Value,
        support: OriginalSourceParameterInterval<F.Value>,using a: inout A) throws
        -> OriginalParametricGraphReceipt<S,F,OriginalCurveParameterGraphEvidence<C,F,E>> where F.Source == F.Value {
        let f=child.field,n=child.layout.variableCount
        try a.admitDepth(value:child.proofDepth.value,coefficient:child.proofDepth.coefficient)
        guard n==child.polynomials.variableCount,child.layout.parameters.count==1,child.support.count==1,
            child.includesUpperBoundary.count==1,child.homogeneous.count==4,
            child.parameterTransport.numerators.count==1,child.parameterTransport.denominators.count==1,
            try f.sign(of:gain,using:&a) != .zero else { throw OriginalSourceIssuanceFailure.invalidChart }
        let lower=try f.importing(support.lower,using:&a),upper=try f.importing(support.upper,using:&a)
        guard try f.compare(lower,upper,using:&a) != .greater else { throw OriginalSourceIssuanceFailure.invalidChart }
        let variables=n.addingReportingOverflow(1),conditions=child.conditions.count.addingReportingOverflow(5)
        guard !variables.overflow,!conditions.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
        let ring=try ExactPolynomialDomain(field:f,variableCount:variables.partialValue,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:Int.self))
        var map:[Int]=[];map.reserveCapacity(n)
        for index in 0..<n { try a.consumeWork(1);map.append(index+1) }
        func embedded(_ polynomial: ExactPolynomial<F>,_ mapping: [Int],_ a: inout A) throws -> ExactPolynomial<F> {
            try OriginalParametricPolynomialEmbedding.applying(polynomial,map:mapping,ring:ring,field:f,using:&a)
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:ExactPolynomial<F>.self))
        var position:[ExactPolynomial<F>]=[];position.reserveCapacity(4)
        for polynomial in child.homogeneous { position.append(try embedded(polynomial,map,&a)) }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:conditions.partialValue,of:OriginalParametricGraphCondition<F>.self))
        var guards:[OriginalParametricGraphCondition<F>]=[];guards.reserveCapacity(conditions.partialValue)
        for condition in child.conditions {
            try a.consumeWork(1);guards.append(.init(try embedded(condition.polynomial,map,&a),condition.relation))
        }
        let local=child.layout.parameters[0]+1,t=try ring.variable(0,using:&a),q=try ring.variable(local,using:&a)
        let lo=try f.importing(child.support[0].lower,using:&a),hi=try f.importing(child.support[0].upper,using:&a)
        guards.append(.init(try ring.subtracting(q,ring.constant(lo,using:&a),using:&a),.nonnegative))
        guards.append(.init(try ring.subtracting(ring.constant(hi,using:&a),q,using:&a),child.includesUpperBoundary[0] ? .nonnegative:.positive))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
        let parameterMap=[local]
        func correspondence(_ polynomial: ExactPolynomial<F>,_ a: inout A) throws -> ExactPolynomial<F> {
            if polynomial.variableCount==1 { return try embedded(polynomial,parameterMap,&a) }
            guard polynomial.variableCount==n else { throw OriginalSourceIssuanceFailure.invalidChart }
            return try embedded(polynomial,map,&a)
        }
        let numerator=try correspondence(child.parameterTransport.numerators[0],&a)
        let denominator=try correspondence(child.parameterTransport.denominators[0],&a)
        guard try !ring.isZero(denominator,using:&a),try !ring.isZero(position[3],using:&a) else { throw OriginalSourceIssuanceFailure.invalidChart }
        let mapped=try ring.adding(ring.scaled(t,by:gain,using:&a),ring.constant(offset,using:&a),using:&a)
        guards.append(.init(try ring.subtracting(numerator,ring.multiplying(mapped,denominator,using:&a),using:&a),.equal))
        guards.append(.init(denominator,.notEqual));guards.append(.init(position[3],.notEqual))
        let parameters=try ExactPolynomialDomain(field:f,variableCount:1,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:ExactPolynomial<F>.self))
        let identity=OriginalRationalParameterTransport<F>(numerators:[try parameters.variable(0,using:&a)],
            denominators:[try parameters.constant(f.integer(1,using:&a),using:&a)])
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
        let layout=try OriginalParametricVariableLayout.checked(variableCount:variables.partialValue,parameters:[0],auxiliaries:map,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourceParameterInterval<F.Value>.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Bool.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalParametricGraphReceipt<S,F,OriginalCurveParameterGraphEvidence<C,F,E>>.self))
        let result=OriginalParametricGraphReceipt(source:source,evidence:OriginalCurveParameterGraphEvidence(child:child),field:f,
            polynomials:ring,homogeneous:position,support:[.init(lower:lower,upper:upper)],includesUpperBoundary:[true],
            layout:layout,conditions:guards,parameterTransport:identity,proofDepth:try a.depth)
        try a.checkpoint();return result
    }
}
