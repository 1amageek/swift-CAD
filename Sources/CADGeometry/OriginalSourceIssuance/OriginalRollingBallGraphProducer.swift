#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// One source-owned minor-arc expression for Native laws and guarded child graphs.
struct OriginalRollingBallGraphProducer<S: OriginalRollingBallChildSourceReading> {
    typealias Field = OriginalExactScalarDomain
    typealias Polynomial = ExactPolynomial<Field>

    func embedded<A: ExactScalarAdmission & ~Copyable>(_ p: Polynomial,map: [Int],
        ring: ExactPolynomialDomain<Field>,field: Field,using a: inout A) throws -> Polynomial {
        try OriginalParametricPolynomialEmbedding.applying(p,map:map,ring:ring,field:field,using:&a)
    }

    func issue<A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<S>,
        evidence: OriginalRollingBallGraphEvidence<S>,lower: Field.Value,upper: Field.Value,
        using a: inout A) throws -> OriginalParametricGraphReceipt<S,Field,OriginalRollingBallGraphEvidence<S>>
        where S: OriginalRollingBallSourceReading {
        let f=evidence.center.field,ring=try ExactPolynomialDomain(field:f,variableCount:5,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:OriginalRationalChartReceipt<S.Child,OriginalBSplineChartSelection,Field>.self))
        let laws=[evidence.center,evidence.first,evidence.second]
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:[Polynomial].self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:OriginalParametricGraphCondition<Field>.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
        let map=[0]
        var positions:[[Polynomial]]=[],guards:[OriginalParametricGraphCondition<Field>]=[]
        positions.reserveCapacity(3);guards.reserveCapacity(3)
        for law in laws {
            try a.consumeWork(1);try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Polynomial.self))
            var coordinates:[Polynomial]=[];coordinates.reserveCapacity(4)
            for p in law.homogeneous { coordinates.append(try embedded(p,map:map,ring:ring,field:f,using:&a)) }
            positions.append(coordinates)
            guards.append(.init(try embedded(law.parameterTransport.denominators[0],map:map,ring:ring,field:f,using:&a),.notEqual))
        }
        return try produce(source:source,evidence:evidence,field:f,ring:ring,children:positions,
            childConditions:guards,lower:lower,upper:upper,using:&a)
    }

    func issue<E: Sendable,A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<S>,
        evidence: OriginalRollingBallChildGraphEvidence<S,E>,field f: Field,lower: Field.Value,upper: Field.Value,
        using a: inout A) throws -> OriginalParametricGraphReceipt<S,Field,OriginalRollingBallChildGraphEvidence<S,E>> {
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:OriginalRollingBallChildGraphEvidence<S,E>.ChildGraph.self))
        let children=[evidence.center,evidence.first,evidence.second]
        var variableCount=5,conditionCount=0
        for child in children {
            try a.consumeWork(1)
            let variables=variableCount.addingReportingOverflow(child.layout.auxiliaries.count)
            let local=child.conditions.count.addingReportingOverflow(3)
            let conditions=conditionCount.addingReportingOverflow(local.partialValue)
            guard !variables.overflow,!local.overflow,!conditions.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            variableCount=variables.partialValue;conditionCount=conditions.partialValue
        }
        let ring=try ExactPolynomialDomain(field:f,variableCount:variableCount,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:[Polynomial].self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:conditionCount,of:OriginalParametricGraphCondition<Field>.self))
        var positions:[[Polynomial]]=[],guards:[OriginalParametricGraphCondition<Field>]=[]
        positions.reserveCapacity(3);guards.reserveCapacity(conditionCount)
        var next=2
        for child in children {
            try a.consumeWork(1)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:child.layout.variableCount,of:Int.self))
            var map=[Int](repeating:0,count:child.layout.variableCount)
            for index in child.layout.auxiliaries { try a.consumeWork(1);map[index]=next;next += 1 }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Polynomial.self))
            var coordinates:[Polynomial]=[];coordinates.reserveCapacity(4)
            for p in child.homogeneous { coordinates.append(try embedded(p,map:map,ring:ring,field:f,using:&a)) }
            positions.append(coordinates)
            for condition in child.conditions {
                try a.consumeWork(1)
                guards.append(.init(try embedded(condition.polynomial,map:map,ring:ring,field:f,using:&a),condition.relation))
            }
            let u=try ring.variable(0,using:&a)
            let lo=try f.importing(child.support[0].lower,using:&a),hi=try f.importing(child.support[0].upper,using:&a)
            guards.append(.init(try ring.subtracting(u,ring.constant(lo,using:&a),using:&a),.nonnegative))
            guards.append(.init(try ring.subtracting(ring.constant(hi,using:&a),u,using:&a),child.includesUpperBoundary[0] ? .nonnegative:.positive))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
            guards.append(.init(try embedded(child.parameterTransport.denominators[0],map:[0],ring:ring,field:f,using:&a),.notEqual))
        }
        return try produce(source:source,evidence:evidence,field:f,ring:ring,children:positions,
            childConditions:guards,lower:lower,upper:upper,using:&a)
    }

    private func produce<E: Sendable,A: ExactScalarAdmission & ~Copyable>(source: OriginalSourceBinding<S>,evidence: E,
        field f: Field,ring: ExactPolynomialDomain<Field>,children: [[Polynomial]],
        childConditions: [OriginalParametricGraphCondition<Field>],lower: Field.Value,upper: Field.Value,
        using a: inout A) throws -> OriginalParametricGraphReceipt<S,Field,E> {
        func add(_ x: Polynomial, _ y: Polynomial) throws -> Polynomial { try ring.adding(x, y, using: &a) }
        func sub(_ x: Polynomial, _ y: Polynomial) throws -> Polynomial { try ring.subtracting(x, y, using: &a) }
        func mul(_ x: Polynomial, _ y: Polynomial) throws -> Polynomial { try ring.multiplying(x, y, using: &a) }
        func square(_ x: Polynomial) throws -> Polynomial { try mul(x, x) }
        let zero = try f.integer(0, using: &a), one = try f.integer(1, using: &a)
        let constantOne = try ring.constant(one, using: &a)
        let v = try ring.variable(1, using: &a), s = try sub(constantOne, v)
        let q1 = try ring.variable(ring.variableCount-3, using: &a), q2 = try ring.variable(ring.variableCount-2, using: &a)
        let w = try ring.variable(ring.variableCount-1, using: &a)
        let dc = children[0][3], d1 = children[1][3]
        let d2 = children[2][3], d = try mul(mul(dc,d1),d2)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 9, of: Polynomial.self))
        var center: [Polynomial] = [], first: [Polynomial] = [], second: [Polynomial] = []
        center.reserveCapacity(3); first.reserveCapacity(3); second.reserveCapacity(3)
        var aa = try ring.constant(zero, using: &a), bb = aa, ab = aa
        for axis in 0..<3 {
            try a.consumeWork(1)
            let c = children[0][axis]
            let x = try mul(sub(mul(children[1][axis],dc),mul(c,d1)),d2)
            let y = try mul(sub(mul(children[2][axis],dc),mul(c,d2)),d1)
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
        let conditionCount=childConditions.count.addingReportingOverflow(18)
        guard !conditionCount.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: conditionCount.partialValue, of: OriginalParametricGraphCondition<Field>.self))
        var guarded: [OriginalParametricGraphCondition<Field>] = []; guarded.reserveCapacity(conditionCount.partialValue)
        func guardLaw(_ p: Polynomial, _ relation: OriginalParametricGraphCondition<Field>.Relation) { guarded.append(.init(p,relation)) }
        guardLaw(q1Equation,.equal); guardLaw(q2Equation,.equal); guardLaw(halfAngleEquation,.equal)
        guardLaw(q1,.positive); guardLaw(q2,.positive); guardLaw(w,.positive)
        guardLaw(try sub(q1,normalization),.positive); guardLaw(try sub(q2,normalization),.positive)
        guardLaw(try sub(q1,lowerRadius),.nonnegative); guardLaw(try sub(upperRadius,q1),.nonnegative)
        guardLaw(try sub(q2,lowerRadius),.nonnegative); guardLaw(try sub(upperRadius,q2),.nonnegative)
        guardLaw(regularArc,.positive); guardLaw(dc,.notEqual); guardLaw(d1,.notEqual); guardLaw(d2,.notEqual)
        guardLaw(denominator,.positive); guardLaw(position[3],.notEqual)
        for condition in childConditions { try a.consumeWork(1);guarded.append(condition) }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: ring.variableCount, of: Int.self))
        try a.consumeWork(ring.variableCount-2)
        let layout = try OriginalParametricVariableLayout.checked(variableCount: ring.variableCount,
            parameters: [0,1], auxiliaries: Array(2..<ring.variableCount), using: &a)
        let parameters = try ExactPolynomialDomain(field: f, variableCount: 2, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Polynomial.self))
        let identity = OriginalRationalParameterTransport<Field>(numerators: [try parameters.variable(0,using:&a),try parameters.variable(1,using:&a)],
            denominators: [try parameters.constant(one,using:&a),try parameters.constant(one,using:&a)])
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: OriginalSourceParameterInterval<Field.Value>.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Bool.self))
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalParametricGraphReceipt<S,Field,E>.self))
        let result = OriginalParametricGraphReceipt<S,Field,E>(source: source, evidence: evidence, field: f, polynomials: ring,
            homogeneous: position, support: [.init(lower: lower,upper: upper),.init(lower: zero,upper: one)],
            includesUpperBoundary: [true,true], layout: layout, conditions: guarded,
            parameterTransport: identity, proofDepth: try a.depth)
        try a.checkpoint(); return result
    }
}
