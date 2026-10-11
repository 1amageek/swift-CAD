#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Eliminates only auxiliary coordinates uniquely fixed by retained exact equalities.
public struct DefaultOriginalPolynomialSurfaceLiftGraphReducer<S: OriginalLiftGraphSourceReading>: OriginalPolynomialSurfaceLiftGraphReducing {
    public typealias Source = S
    public typealias Reduction = OriginalPolynomialSurfaceLiftGraphReduction<S>
    typealias Field = OriginalExactScalarDomain
    typealias Polynomial = ExactPolynomial<Field>
    public init() {}
    public func reduce<A: ExactScalarAdmission & ~Copyable>(_ graph: borrowing Reduction.Graph,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> Reduction {
        let original = copy graph
        do {
            return try OriginalSourceProofAdmission<A>.withBorrow(&admission) { a in
                try a.checkpoint(); try original.source.require(limits)
                try a.admitDepth(value:original.proofDepth.value,coefficient:original.proofDepth.coefficient)
                guard original.layout.variableCount == 3,original.layout.parameters == [0],
                    original.layout.auxiliaries == [1,2],original.support.count == 1,
                    original.homogeneous.count == 4 else { throw OriginalSourceIssuanceFailure.invalidChart }
                let f = original.field,r = original.polynomials
                let reduced = try ExactPolynomialDomain(field:f,variableCount:1,using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Polynomial.self))
                var replacements: [Polynomial] = []; replacements.reserveCapacity(3)
                replacements.append(try r.variable(0,using:&a))
                for axis in 1...2 {
                    try a.consumeWork(1)
                    var replacement: Polynomial?
                    for condition in original.conditions where condition.relation == .equal {
                        try a.consumeWork(1)
                        var coefficient: Field.Value?, valid = true
                        for term in condition.polynomial.terms {
                            try a.consumeWork(1)
                            guard term.powers.count == 3 else { throw OriginalSourceIssuanceFailure.invalidChart }
                            if term.powers[1] == 0 && term.powers[2] == 0 { continue }
                            if term.powers[axis] == 1 && term.powers[0] == 0 && term.powers[3-axis] == 0 && coefficient == nil {
                                coefficient = term.coefficient
                            } else { valid = false; break }
                        }
                        guard valid,let coefficient,try f.sign(of:coefficient,using:&a) != .zero else { continue }
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:condition.polynomial.termCount,of:ExactPolynomialTerm<Field.Value>.self))
                        var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(condition.polynomial.termCount)
                        for term in condition.polynomial.terms where term.powers[1] == 0 && term.powers[2] == 0 {
                            try a.consumeWork(1)
                            terms.append(.init(powers:term.powers,coefficient:try f.dividing(f.negated(term.coefficient,using:&a),coefficient,using:&a)))
                        }
                        replacement = try r.polynomial(terms:terms,using:&a); break
                    }
                    guard let replacement else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
                    replacements.append(replacement)
                }
                func project(_ law: Polynomial) throws -> Polynomial {
                    try a.admitDepth(value:law.depth.value,coefficient:law.depth.coefficient)
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:law.termCount,of:ExactPolynomialTerm<Field.Value>.self))
                    var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(law.termCount)
                    for term in law.terms {
                        try a.consumeWork(1)
                        guard term.powers.count == 3,term.powers[1] == 0,term.powers[2] == 0 else { throw OriginalSourceIssuanceFailure.invalidChart }
                        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Int.self))
                        terms.append(.init(powers:[term.powers[0]],coefficient:term.coefficient))
                    }
                    return try reduced.polynomial(terms:terms,using:&a)
                }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:Polynomial.self))
                var coordinates: [Polynomial] = []; coordinates.reserveCapacity(3)
                for law in replacements { coordinates.append(try project(law)) }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Polynomial.self))
                var position: [Polynomial] = []; position.reserveCapacity(4)
                for law in original.homogeneous { position.append(try project(r.substituted(law,with:replacements,using:&a))) }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:original.conditions.count,of:OriginalParametricGraphCondition<Field>.self))
                var conditions: [OriginalParametricGraphCondition<Field>] = []; conditions.reserveCapacity(original.conditions.count)
                for condition in original.conditions {
                    try a.consumeWork(1)
                    conditions.append(.init(try project(r.substituted(condition.polynomial,with:replacements,using:&a)),condition.relation))
                }
                let layout = try OriginalParametricVariableLayout.checked(variableCount:1,parameters:[0],auxiliaries:[],using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Reduction.Graph.self))
                let result = Reduction.Graph(source:original.source,evidence:original.evidence,field:f,polynomials:reduced,
                    homogeneous:position,support:original.support,includesUpperBoundary:original.includesUpperBoundary,
                    layout:layout,conditions:conditions,parameterTransport:original.parameterTransport,proofDepth:try a.depth)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Reduction.self))
                let receipt = Reduction(original:original,graph:result,originalCoordinates:coordinates)
                try a.checkpoint(); return receipt
            }
        } catch { throw .init(preserving:error) }
    }
}
