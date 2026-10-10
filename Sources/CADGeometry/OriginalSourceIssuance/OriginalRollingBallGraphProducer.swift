#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Source-owned polynomial form of the retained minor-arc expression.
struct OriginalRollingBallGraphProducer<S: OriginalRollingBallSourceReading> {
    typealias Field = OriginalExactScalarDomain
    typealias Polynomial = ExactPolynomial<Field>
    typealias Evidence = OriginalRollingBallGraphEvidence<S>
    typealias Graph = OriginalParametricGraphReceipt<S, Field, Evidence>

    func issue<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<S>,
        evidence: Evidence, lower: Field.Value, upper: Field.Value,
        using a: inout OriginalSourceProofAdmission<A>) throws -> Graph {
        let f = evidence.center.field
        let ring = try ExactPolynomialDomain(field: f, variableCount: 5, using: &a)
        func add(_ x: Polynomial, _ y: Polynomial) throws -> Polynomial { try ring.adding(x, y, using: &a) }
        func sub(_ x: Polynomial, _ y: Polynomial) throws -> Polynomial { try ring.subtracting(x, y, using: &a) }
        func mul(_ x: Polynomial, _ y: Polynomial) throws -> Polynomial { try ring.multiplying(x, y, using: &a) }
        func square(_ x: Polynomial) throws -> Polynomial { try mul(x, x) }
        func embed(_ p: Polynomial) throws -> Polynomial {
            try a.admitDepth(value: p.depth.value, coefficient: p.depth.coefficient)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: p.termCount, of: ExactPolynomialTerm<Field.Value>.self))
            var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(p.termCount)
            for term in p.terms {
                try a.consumeWork(1)
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: 5, of: Int.self))
                terms.append(.init(powers: [term.powers[0],0,0,0,0], coefficient: try f.importing(term.coefficient, using: &a)))
            }
            return try ring.polynomial(orderedTerms: terms, using: &a)
        }
        let zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a)
        let constantOne = try ring.constant(one, using: &a)
        let v = try ring.variable(1, using: &a), s = try sub(constantOne, v)
        let q1 = try ring.variable(2, using: &a), q2 = try ring.variable(3, using: &a)
        let w = try ring.variable(4, using: &a)
        let dc = try embed(evidence.center.denominator), d1 = try embed(evidence.first.denominator)
        let d2 = try embed(evidence.second.denominator), d = try mul(mul(dc,d1),d2)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 9, of: Polynomial.self))
        var center: [Polynomial] = [], first: [Polynomial] = [], second: [Polynomial] = []
        center.reserveCapacity(3); first.reserveCapacity(3); second.reserveCapacity(3)
        var aa = try ring.constant(zero, using: &a), bb = aa, ab = aa
        for axis in 0..<3 {
            try a.consumeWork(1)
            let c = try embed(evidence.center.homogeneous[axis])
            let x = try mul(sub(mul(embed(evidence.first.homogeneous[axis]),dc),mul(c,d1)),d2)
            let y = try mul(sub(mul(embed(evidence.second.homogeneous[axis]),dc),mul(c,d2)),d1)
            center.append(c); first.append(x); second.append(y)
            aa = try add(aa,square(x)); bb = try add(bb,square(y)); ab = try add(ab,mul(x,y))
        }
        let dSquared = try square(d), qProduct = try mul(q1,q2), h = try mul(dSquared,qProduct)
        let sv = try mul(s,v), sSquared = try square(s), vSquared = try square(v)
        let two = try f.integer(2, using: &a)
        let denominator = try add(add(sSquared,ring.scaled(mul(w,sv),by:two,using:&a)),vSquared)
        let radialDenominator = try mul(mul(mul(d,qProduct),w),denominator)
        let radius = try f.binary64(exactly: source.original.originalRadius, using: &a)
        let tolerance = try f.binary64(exactly: source.original.originalDistanceTolerance, using: &a)
        let threshold = try f.binary64(exactly: source.original.originalRadialCrossThreshold, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Polynomial.self))
        var position: [Polynomial] = []; position.reserveCapacity(4)
        for axis in 0..<3 {
            try a.consumeWork(1)
            let x = first[axis], y = second[axis]
            let middle = try mul(add(mul(x,q2),mul(y,q1)),sv)
            let radial = try add(add(mul(mul(mul(x,q2),w),sSquared),middle),mul(mul(mul(y,q1),w),vSquared))
            position.append(try add(mul(center[axis],radialDenominator),ring.scaled(mul(dc,radial),by:radius,using:&a)))
        }
        position.append(try mul(dc,radialDenominator))
        // q1/q2 are physical radial lengths; their positive branches fix denominator signs.
        let q1Equation = try sub(mul(square(q1),dSquared),aa)
        let q2Equation = try sub(mul(square(q2),dSquared),bb)
        let halfAngleEquation = try sub(sub(ring.scaled(mul(square(w),h),by:two,using:&a),h),ab)
        let regularArc = try sub(sub(mul(aa,bb),square(ab)),ring.scaled(square(h),by:f.multiplying(threshold,threshold,using:&a),using:&a))
        let lowerRadius = try ring.constant(f.subtracting(radius,tolerance,using:&a),using:&a)
        let upperRadius = try ring.constant(f.adding(radius,tolerance,using:&a),using:&a)
        let normalization = try ring.constant(tolerance,using:&a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 21, of: OriginalParametricGraphCondition<Field>.self))
        var guarded: [OriginalParametricGraphCondition<Field>] = []; guarded.reserveCapacity(21)
        func guardLaw(_ p: Polynomial, _ relation: OriginalParametricGraphCondition<Field>.Relation) { guarded.append(.init(p,relation)) }
        guardLaw(q1Equation,.equal); guardLaw(q2Equation,.equal); guardLaw(halfAngleEquation,.equal)
        guardLaw(q1,.positive); guardLaw(q2,.positive); guardLaw(w,.positive)
        guardLaw(try sub(q1,normalization),.positive); guardLaw(try sub(q2,normalization),.positive)
        guardLaw(try sub(q1,lowerRadius),.nonnegative); guardLaw(try sub(upperRadius,q1),.nonnegative)
        guardLaw(try sub(q2,lowerRadius),.nonnegative); guardLaw(try sub(upperRadius,q2),.nonnegative)
        guardLaw(regularArc,.positive); guardLaw(dc,.notEqual); guardLaw(d1,.notEqual); guardLaw(d2,.notEqual)
        guardLaw(denominator,.positive); guardLaw(position[3],.notEqual)
        // Identity correspondence does not remove its original denominator guards.
        guardLaw(try embed(evidence.center.parameterTransport.denominators[0]),.notEqual)
        guardLaw(try embed(evidence.first.parameterTransport.denominators[0]),.notEqual)
        guardLaw(try embed(evidence.second.parameterTransport.denominators[0]),.notEqual)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 5, of: Int.self))
        let layout = try OriginalParametricVariableLayout.checked(variableCount: 5, parameters: [0,1], auxiliaries: [2,3,4], using: &a)
        let parameters = try ExactPolynomialDomain(field: f, variableCount: 2, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Polynomial.self))
        let identity = OriginalRationalParameterTransport<Field>(numerators: [try parameters.variable(0,using:&a),try parameters.variable(1,using:&a)],
            denominators: [try parameters.constant(one,using:&a),try parameters.constant(one,using:&a)])
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: OriginalSourceParameterInterval<Field.Value>.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Bool.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Graph.self))
        let result = Graph(source: source, evidence: evidence, field: f, polynomials: ring,
            homogeneous: position, support: [.init(lower: lower,upper: upper),.init(lower: zero,upper: one)],
            includesUpperBoundary: [true,true], layout: layout, conditions: guarded,
            parameterTransport: identity, proofDepth: try a.depth)
        try a.checkpoint(); return result
    }
}
