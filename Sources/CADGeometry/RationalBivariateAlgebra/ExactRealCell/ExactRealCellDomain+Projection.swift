#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

extension ExactRealCellDomain {
    func coefficientVector<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial, axis: Int, _ a: inout A) throws -> [Polynomial] {
        guard let degree = try polynomials.degree(of: law, in: axis, using: &a) else { return [] }
        let count = try ExactCellAccess.add(degree, 1)
        try ExactCellAccess.storage(count, Polynomial.self, &a)
        if degree == 0 { return [law] }
        try ExactCellAccess.storage(count, Int.self, &a)
        var counts = Array(repeating: 0, count: count)
        for term in law.terms {
            try a.consumeWork(1)
            counts[term.powers[axis]] = try ExactCellAccess.add(counts[term.powers[axis]], 1)
        }
        try ExactCellAccess.storage(count, [ExactPolynomialTerm<Field.Value>].self, &a)
        try ExactCellAccess.storage(law.termCount, ExactPolynomialTerm<Field.Value>.self, &a)
        var buckets = Array(repeating: [ExactPolynomialTerm<Field.Value>](), count: count)
        for index in counts.indices { try a.consumeWork(1); buckets[index].reserveCapacity(counts[index]) }
        for term in law.terms {
            try a.consumeWork(1)
            try ExactCellAccess.storage(term.powers.count, Int.self, &a)
            try a.consumeWork(term.powers.count)
            var powers = term.powers; powers[axis] = 0
            buckets[term.powers[axis]].append(.init(powers: powers, coefficient: term.coefficient))
        }
        var result: [Polynomial] = []; result.reserveCapacity(count)
        for terms in buckets {
            result.append(try polynomials.polynomial(terms: terms, using: &a))
        }
        return result
    }
    func normalizedCondition<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial, _ a: inout A) throws -> (Polynomial, Field.Value) {
        guard let first = law.terms.first else { return (law, try context.field.integer(1, using: &a)) }
        let monic = try polynomials.normalized(law, using: &a)
        let negative = try context.field.sign(of: first.coefficient, using: &a) == .negative
        let normalized = try negative ? polynomials.negated(monic, using: &a) : monic
        let multiplier = try negative ? context.field.negated(first.coefficient, using: &a) : first.coefficient
        guard try polynomials.equals(law, polynomials.scaled(normalized, by: multiplier, using: &a), using: &a) else {
            throw ExactRealCellFailure.invalidCoverage
        }
        return (normalized, multiplier)
    }
    func insert<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial, into result: inout [Polynomial],
        witnesses: inout [ExactRealCellProjectionWitness<Base>], _ a: inout A) throws {
        let (normalized, multiplier) = try normalizedCondition(law, &a)
        try ExactCellAccess.storage(1, ExactRealCellProjectionWitness<Base>.self, &a)
        witnesses.append(.normalization(original: law, result: normalized, multiplier: multiplier))
        var nonconstant = false
        for term in normalized.terms {
            try a.consumeWork(term.powers.count)
            for power in term.powers where power != 0 { nonconstant = true }
        }
        if !nonconstant { return }
        for existing in result { if try polynomials.equals(existing, normalized, using: &a) { return } }
        try ExactCellAccess.storage(1, Polynomial.self, &a); result.append(normalized)
    }
    func conditionBindings<A: ExactScalarAdmission & ~Copyable>(_ level: ExactRealCellProjectionLevel<Base>, lower: ExactRealCellProjectionLevel<Base>?,
        _ a: inout A) throws -> [ExactRealCellProjectionBinding<Base>] {
        var result: [ExactRealCellProjectionBinding<Base>] = []
        for witness in level.witnesses {
            let law: Polynomial
            switch witness {
            case .coefficient(_, let value, _, _), .principal(_, _, let value, _, _): law = value
            default: continue
            }
            var duplicate = false
            for binding in result { if try polynomials.equals(binding.polynomial, law, using: &a) { duplicate = true; break } }
            if duplicate { continue }
            let (normalized, multiplier) = try normalizedCondition(law, &a)
            var nonconstant = false
            for term in law.terms { for axis in term.powers.indices {
                try a.consumeWork(1)
                guard axis < level.axis || term.powers[axis] == 0 else { throw ExactRealCellFailure.invalidCoverage }
                if term.powers[axis] != 0 { nonconstant = true }
            } }
            var index: Int? = nil
            if nonconstant {
                guard let lower else { throw ExactRealCellFailure.invalidCoverage }
                for candidate in 0..<lower.cutLawCount {
                    if try polynomials.equals(normalized, lower.laws[candidate], using: &a) { index = candidate; break }
                }
                guard index != nil else { throw ExactRealCellFailure.invalidCoverage }
            }
            try ExactCellAccess.storage(1, ExactRealCellProjectionBinding<Base>.self, &a)
            result.append(.init(polynomial: law, normalized: normalized, multiplier: multiplier, lowerLawIndex: index))
        }
        return result
    }
    func projection<A: ExactScalarAdmission & ~Copyable>(_ source: ExactRealCellSource<Base>, _ a: inout A) throws -> [ExactRealCellProjectionLevel<Base>] {
        try require(source, &a)
        var pending: [Polynomial] = [], inputWitnesses: [ExactRealCellProjectionWitness<Base>] = []
        for law in source.polynomials { try insert(law, into: &pending, witnesses: &inputWitnesses, &a) }
        for axis in source.domains.indices {
            let domain = source.domains[axis]
            try ExactCellAccess.storage(2, ExactRealRootBound<Field.Value>.self, &a)
            for bound in [domain.lower, domain.upper] {
                if case .finite(let value) = bound {
                    let law = try polynomials.subtracting(polynomials.variable(axis, using: &a), polynomials.constant(context.field.importing(value,using:&a), using: &a), using: &a)
                    try insert(law, into: &pending, witnesses: &inputWitnesses, &a)
                }
            }
        }
        try ExactCellAccess.storage(source.variableCount, ExactRealCellProjectionLevel<Base>.self, &a)
        var descending: [ExactRealCellProjectionLevel<Base>] = []
        for axis in (0..<source.variableCount).reversed() {
            var laws: [Polynomial] = [], witnesses: [ExactRealCellProjectionWitness<Base>] = []
            if axis == source.variableCount - 1 { witnesses = inputWitnesses; inputWitnesses = [] }
            for law in pending { try insert(law, into: &laws, witnesses: &witnesses, &a) }
            let cutLawCount = laws.count
            var offset = 0
            while offset < laws.count {
                let law = laws[offset]; offset += 1
                let d = try polynomials.differentiated(law, in: axis, using: &a)
                try ExactCellAccess.storage(1, ExactRealCellProjectionWitness<Base>.self, &a)
                witnesses.append(.derivative(original: law, result: d, axis: axis))
                try insert(d, into: &laws, witnesses: &witnesses, &a)
            }
            var lower: [Polynomial] = [], coefficients: [[Polynomial]] = [], families: [[Polynomial]] = []
            try ExactCellAccess.storage(laws.count, [Polynomial].self, &a)
            try ExactCellAccess.storage(laws.count, [Polynomial].self, &a)
            for law in laws {
                let cs = try coefficientVector(law, axis: axis, &a); coefficients.append(cs)
                for degree in cs.indices {
                    try ExactCellAccess.storage(1, ExactRealCellProjectionWitness<Base>.self, &a)
                    witnesses.append(.coefficient(original: law, result: cs[degree], axis: axis, degree: degree))
                    try insert(cs[degree], into: &lower, witnesses: &witnesses, &a)
                }
                var reducta: [Polynomial] = [], remainder = law
                while let degree = try polynomials.degree(of: remainder, in: axis, using: &a), degree > 0 {
                    try ExactCellAccess.storage(1, Polynomial.self, &a); reducta.append(remainder)
                    let derivative = try polynomials.differentiated(remainder, in: axis, using: &a)
                    if let n = try polynomials.degree(of: derivative, in: axis, using: &a), n > 0 {
                        let sequence = try polynomials.principalSubresultants(remainder,derivative,eliminating:axis,using:&a)
                        try a.consumeWork(1)
                        guard sequence.values.count == min(degree,n) else { throw ExactRealCellFailure.invalidCoverage }
                        for j in sequence.values.indices {
                            let psc = sequence.values[j]
                            try ExactCellAccess.storage(1, ExactRealCellProjectionWitness<Base>.self, &a)
                            witnesses.append(.principal(first: remainder, second: derivative, result: psc, axis: axis, index: j))
                            try insert(psc, into: &lower, witnesses: &witnesses, &a)
                        }
                    }
                    try ExactCellAccess.storage(remainder.termCount, ExactPolynomialTerm<Field.Value>.self, &a)
                    var terms: [ExactPolynomialTerm<Field.Value>] = []
                    for term in remainder.terms {
                        try a.consumeWork(1); if term.powers[axis] != degree { terms.append(term) }
                    }
                    let reductum = try polynomials.polynomial(terms: terms, using: &a)
                    try ExactCellAccess.storage(1, ExactRealCellProjectionWitness<Base>.self, &a)
                    witnesses.append(.reductum(original: remainder, result: reductum, axis: axis, removedDegree: degree))
                    remainder = reductum
                }
                families.append(reducta)
            }
            for i in families.indices { for j in families.indices where j > i {
                for left in families[i] { for right in families[j] {
                    guard let m = try polynomials.degree(of: left, in: axis, using: &a), let n = try polynomials.degree(of: right, in: axis, using: &a) else { throw ExactRealCellFailure.invalidCoverage }
                    let sequence = try polynomials.principalSubresultants(left,right,eliminating:axis,using:&a)
                    try a.consumeWork(1)
                    guard sequence.values.count == min(m,n) else { throw ExactRealCellFailure.invalidCoverage }
                    for k in sequence.values.indices {
                        let psc = sequence.values[k]
                        try ExactCellAccess.storage(1, ExactRealCellProjectionWitness<Base>.self, &a)
                        witnesses.append(.principal(first:left,second:right,result:psc,axis:axis,index:k))
                        try insert(psc,into:&lower,witnesses:&witnesses,&a)
                    }
                } }
            } }
            descending.append(.init(axis:axis,cutLawCount:cutLawCount,laws:laws,coefficients:coefficients,bindings:[],witnesses:witnesses)); pending = lower
        }
        try ExactCellAccess.storage(descending.count, ExactRealCellProjectionLevel<Base>.self, &a)
        let ascending = Array(descending.reversed())
        try ExactCellAccess.storage(ascending.count, ExactRealCellProjectionLevel<Base>.self, &a)
        var result: [ExactRealCellProjectionLevel<Base>] = []; result.reserveCapacity(ascending.count)
        for index in ascending.indices {
            let level = ascending[index]
            let bindings = try conditionBindings(level, lower: index == 0 ? nil : ascending[index - 1], &a)
            result.append(.init(axis: level.axis, cutLawCount: level.cutLawCount, laws: level.laws,
                coefficients: level.coefficients, bindings: bindings, witnesses: level.witnesses))
        }
        return result
    }
}
