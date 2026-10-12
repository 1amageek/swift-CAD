#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Eliminates only uniquely fixed linear or strictly positive constant-square auxiliaries.
struct DefaultOriginalRollingBallGraphReducer<S: OriginalRollingBallChildSourceReading,E: Sendable> {
    typealias Field = OriginalExactScalarDomain
    typealias Polynomial = ExactPolynomial<Field>
    typealias Evidence = OriginalRollingBallGraphReduction<S,E>
    typealias Input = OriginalParametricGraphReceipt<S,Field,OriginalRollingBallChildGraphEvidence<S,E>>
    typealias Output = OriginalParametricGraphReceipt<S,Field,Evidence>

    func reduce<A: ExactScalarAdmission & ~Copyable>(_ original: Input,
        limits: OriginalSourceIssuanceLimits, reusing prior: Output? = nil, using admission: inout A) throws -> Output {
        try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
            try a.checkpoint(); try original.source.require(limits)
            try a.admitDepth(value:original.proofDepth.value,coefficient:original.proofDepth.coefficient)
            let f = original.field, n = original.polynomials.variableCount
            guard n >= 2, original.layout.parameters == [0,1], original.layout.auxiliaries.count == n-2,
                original.homogeneous.count == 4 else { throw OriginalSourceIssuanceFailure.invalidChart }
            for i in original.layout.auxiliaries.indices {
                try a.consumeWork(1)
                guard original.layout.auxiliaries[i] == i+2 else { throw OriginalSourceIssuanceFailure.invalidChart }
            }
            func equal(_ x: Input,_ y: Input) throws -> Bool {
                guard x.layout.variableCount == y.layout.variableCount else { return false }
                var cursor = 0
                for c in x.conditions where c.relation == .equal || c.relation == .positive {
                    while cursor < y.conditions.count && y.conditions[cursor].relation != .equal && y.conditions[cursor].relation != .positive { cursor += 1; try a.consumeWork(1) }
                    guard cursor < y.conditions.count else { return false }
                    let d = y.conditions[cursor]; cursor += 1
                    guard c.relation == d.relation, c.polynomial.terms.count == d.polynomial.terms.count else { return false }
                    for i in c.polynomial.terms.indices {
                        let l = c.polynomial.terms[i], r = d.polynomial.terms[i]
                        try a.consumeWork(l.powers.count)
                        guard l.powers == r.powers, try f.compare(l.coefficient,r.coefficient,using:&a) == .equal else { return false }
                    }
                }
                while cursor < y.conditions.count {
                    try a.consumeWork(1)
                    if y.conditions[cursor].relation == .equal || y.conditions[cursor].relation == .positive { return false }
                    cursor += 1
                }
                return true
            }
            let reused = try prior.map { try equal(original,$0.evidence.original) } ?? false
            let ring = try reused ? prior!.polynomials:ExactPolynomialDomain(field:f,variableCount:2,using:&a)
            let zero = try f.integer(0,using:&a), one = try f.integer(1,using:&a)
            let zeroLaw = try ring.constant(zero,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:Polynomial.self))
            var coordinates = [try ring.variable(0,using:&a),try ring.variable(1,using:&a)]
            coordinates.reserveCapacity(n)
            func constant(_ law: Polynomial) -> Field.Value? {
                if law.terms.isEmpty { return zero }
                if law.terms.count == 1, law.terms[0].powers.allSatisfy({ $0 == 0 }) { return law.terms[0].coefficient }
                return nil
            }
            // Substitute directly into UV, avoiding eleven-dimensional intermediate terms.
            func substitute(_ law: Polynomial, formal: Int? = nil) throws -> [Polynomial] {
                try a.admitDepth(value:law.depth.value,coefficient:law.depth.coefficient)
                let count = formal == nil ? 1:3
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:count,of:Polynomial.self))
                var coefficients = [Polynomial](repeating:zeroLaw,count:count)
                for term in law.terms {
                    try a.consumeWork(1)
                    let power = formal.map { term.powers[$0] } ?? 0
                    guard power < count else { throw OriginalSourceIssuanceFailure.invalidChart }
                    var coefficient = term.coefficient
                    var product = try ring.constant(one,using:&a)
                    for axis in 0..<n where axis != formal && term.powers[axis] != 0 {
                        try a.consumeWork(1)
                        guard axis < coordinates.count else { throw OriginalSourceIssuanceFailure.invalidChart }
                        var exponent = term.powers[axis]
                        if let value = constant(coordinates[axis]) {
                            var factor = value
                            while exponent > 0 {
                                if exponent & 1 != 0 { coefficient = try f.multiplying(coefficient,factor,using:&a) }
                                exponent /= 2
                                if exponent > 0 { factor = try f.multiplying(factor,factor,using:&a) }
                            }
                        } else {
                            var factor = coordinates[axis]
                            while exponent > 0 {
                                if exponent & 1 != 0 { product = try ring.multiplying(product,factor,using:&a) }
                                exponent /= 2
                                if exponent > 0 { factor = try ring.multiplying(factor,factor,using:&a) }
                            }
                        }
                    }
                    coefficients[power] = try ring.adding(coefficients[power],ring.scaled(product,by:coefficient,using:&a),using:&a)
                }
                return coefficients
            }
            if reused, let prior {
                try a.admitDepth(value:prior.proofDepth.value,coefficient:prior.proofDepth.coefficient)
                coordinates = prior.evidence.originalCoordinates
            }
            for axis in (reused ? n:2)..<n {
                var selected: Polynomial?
                for condition in original.conditions where condition.relation == .equal {
                    try a.consumeWork(1)
                    var eligible = false
                    for term in condition.polynomial.terms {
                        try a.consumeWork(1)
                        if term.powers[axis] != 0 { eligible = true }
                        if term.powers[axis] > 2 || ((axis+1)..<n).contains(where:{ term.powers[$0] != 0 }) {
                            eligible = false; break
                        }
                    }
                    guard eligible else { continue }
                    let coefficients = try substitute(condition.polynomial,formal:axis)
                    if coefficients[2].terms.isEmpty, let c = constant(coefficients[1]),
                        try f.sign(of:c,using:&a) != .zero {
                        selected = try ring.scaled(coefficients[0],by:f.dividing(f.integer(-1,using:&a),c,using:&a),using:&a)
                    } else if coefficients[1].terms.isEmpty, let c = constant(coefficients[2]),
                        let rest = constant(coefficients[0]), try f.sign(of:c,using:&a) != .zero {
                        var positive = false
                        for guardLaw in original.conditions where guardLaw.relation == .positive {
                            try a.consumeWork(1)
                            let terms = guardLaw.polynomial.terms
                            if terms.count == 1, terms[0].powers[axis] == 1,
                                terms[0].powers.enumerated().allSatisfy({ $0.offset == axis || $0.element == 0 }),
                                try f.sign(of:terms[0].coefficient,using:&a) == .positive { positive = true; break }
                        }
                        guard positive else { continue }
                        let radicand = try f.dividing(f.negated(rest,using:&a),c,using:&a)
                        guard let value = try f.exactRationalSquareRoot(of:radicand,using:&a) else { continue }
                        guard try f.sign(of:value,using:&a) == .positive else { continue }
                        selected = try ring.constant(value,using:&a)
                    }
                    if selected != nil { break }
                }
                guard let selected else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                coordinates.append(selected)
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Polynomial.self))
            var position: [Polynomial] = []; position.reserveCapacity(4)
            for law in original.homogeneous { position.append(try substitute(law)[0]) }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:original.conditions.count,of:OriginalParametricGraphCondition<Field>.self))
            var conditions: [OriginalParametricGraphCondition<Field>] = []; conditions.reserveCapacity(original.conditions.count)
            for condition in original.conditions { conditions.append(.init(try substitute(condition.polynomial)[0],condition.relation)) }
            let layout = try OriginalParametricVariableLayout.checked(variableCount:2,parameters:[0,1],auxiliaries:[],using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Evidence.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Output.self))
            let result = Output(source:original.source,evidence:.init(original:original,originalCoordinates:coordinates),field:f,
                polynomials:ring,homogeneous:position,support:original.support,includesUpperBoundary:original.includesUpperBoundary,
                layout:layout,conditions:conditions,parameterTransport:original.parameterTransport,proofDepth:try a.depth)
            try a.checkpoint(); return result
        }
    }
}
