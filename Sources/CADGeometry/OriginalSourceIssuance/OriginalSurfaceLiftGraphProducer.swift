#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact forward composition; auxiliary UV is never recovered through an inverse.
struct OriginalSurfaceLiftGraphProducer<S: OriginalLiftGraphSourceReading> {
    typealias Field=OriginalExactScalarDomain
    typealias Polynomial=ExactPolynomial<Field>
    typealias Graph=OriginalParametricGraphReceipt<S,Field,OriginalSurfaceLiftGraphEvidence<S>>
    func issue<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<S>,
        evidence: OriginalSurfaceLiftGraphEvidence<S>,offset: Field.Value,span: Field.Value,
        using a: inout A) throws -> Graph {
        let f=evidence.surface.field
        let ring=try ExactPolynomialDomain(field:f,variableCount:3,using:&a)
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        let t=try ring.variable(0,using:&a),u=try ring.variable(1,using:&a),v=try ring.variable(2,using:&a)
        let localU: Polynomial,localV: Polynomial
        if let shift=evidence.surfaceTranslation {
            guard shift.count == 2 else { throw OriginalSourceIssuanceFailure.invalidChart }
            localU=try ring.subtracting(u,ring.constant(shift[0],using:&a),using:&a)
            localV=try ring.subtracting(v,ring.constant(shift[1],using:&a),using:&a)
        } else { localU=u;localV=v }
        let tau=try ring.adding(ring.constant(offset,using:&a),ring.scaled(t,by:span,using:&a),using:&a)
        func embed(_ p: Polynomial,surface: Bool) throws -> Polynomial {
            try a.admitDepth(value:p.depth.value,coefficient:p.depth.coefficient)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:p.termCount,of:ExactPolynomialTerm<Field.Value>.self))
            var terms:[ExactPolynomialTerm<Field.Value>]=[];terms.reserveCapacity(p.termCount)
            for term in p.terms {
                try a.consumeWork(1);try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Int.self))
                let powers=surface ? [0,term.powers[0],term.powers[1]]:[term.powers[0],0,0]
                terms.append(.init(powers:powers,coefficient:try f.importing(term.coefficient,using:&a)))
            }
            let result=try ring.polynomial(orderedTerms:terms,using:&a)
            if surface {
                if evidence.surfaceTranslation == nil { return result }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Polynomial.self))
                return try ring.substituted(result,with:[t,localU,localV],using:&a)
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Polynomial.self))
            return try ring.substituted(result,with:[tau,u,v],using:&a)
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Polynomial.self))
        var position:[Polynomial]=[];position.reserveCapacity(4)
        for p in evidence.surface.homogeneous { try a.consumeWork(1);position.append(try embed(p,surface:true)) }
        let dp=try embed(evidence.pcurve.denominator,surface:false)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:11,of:OriginalParametricGraphCondition<Field>.self))
        var guards:[OriginalParametricGraphCondition<Field>]=[];guards.reserveCapacity(11)
        for axis in 0..<2 {
            try a.consumeWork(1)
            let coordinate=axis == 0 ? u:v,local=axis == 0 ? localU:localV,bound=evidence.surface.support[axis]
            guards.append(.init(try ring.subtracting(ring.multiplying(coordinate,dp,using:&a),
                embed(evidence.pcurve.homogeneous[axis],surface:false),using:&a),.equal))
            guards.append(.init(try ring.subtracting(local,ring.constant(bound.lower,using:&a),using:&a),.nonnegative))
            guards.append(.init(try ring.subtracting(ring.constant(bound.upper,using:&a),local,using:&a),.nonnegative))
            guards.append(.init(try embed(evidence.surface.parameterTransport.denominators[axis],surface:true),.notEqual))
        }
        guards.append(.init(dp,.notEqual));guards.append(.init(position[3],.notEqual))
        guards.append(.init(try embed(evidence.pcurve.parameterTransport.denominators[0],surface:false),.notEqual))
        let parameters=try ExactPolynomialDomain(field:f,variableCount:1,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Polynomial.self))
        let identity=OriginalRationalParameterTransport<Field>(numerators:[try parameters.variable(0,using:&a)],
            denominators:[try parameters.constant(one,using:&a)])
        let lower=try f.dividing(f.subtracting(f.importing(evidence.pcurve.support[0].lower,using:&a),offset,using:&a),span,using:&a)
        let upper=try f.dividing(f.subtracting(f.importing(evidence.pcurve.support[0].upper,using:&a),offset,using:&a),span,using:&a)
        guard try f.compare(lower,zero,using:&a) != .less,try f.compare(upper,one,using:&a) != .greater else {
            throw OriginalSourceIssuanceFailure.invalidChart
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Int.self))
        let layout=try OriginalParametricVariableLayout.checked(variableCount:3,parameters:[0],auxiliaries:[1,2],using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSourceParameterInterval<Field.Value>.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Bool.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Graph.self))
        let result=Graph(source:source,evidence:evidence,field:f,polynomials:ring,homogeneous:position,
            support:[.init(lower:lower,upper:upper)],includesUpperBoundary:[true],layout:layout,
            conditions:guards,parameterTransport:identity,proofDepth:try a.depth)
        try a.checkpoint();return result
    }
}
