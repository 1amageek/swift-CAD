#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

extension ExactRealCellDomain {
    func coefficientVector(_ law: Polynomial, axis: Int, _ a: inout ExactCellBorrowedAdmission) throws -> [Polynomial] {
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
    func insert(_ law: Polynomial, into result: inout [Polynomial], _ a: inout ExactCellBorrowedAdmission) throws {
        guard !law.terms.isEmpty else { return }
        var nonconstant = false
        for term in law.terms {
            try a.consumeWork(term.powers.count)
            for power in term.powers where power != 0 { nonconstant = true }
        }
        if !nonconstant { return }
        let normalized = law
        for existing in result { if try polynomials.equals(existing, normalized, using: &a) { return } }
        try ExactCellAccess.storage(1, Polynomial.self, &a); result.append(normalized)
    }
    func projection(_ source: ExactRealCellSource<Base>, _ a: inout ExactCellBorrowedAdmission) throws -> [ExactRealCellProjectionLevel<Base>] {
        try require(source, &a)
        var pending: [Polynomial] = []
        for law in source.polynomials { try insert(law, into: &pending, &a) }
        for axis in source.domains.indices {
            let domain = source.domains[axis]
            try ExactCellAccess.storage(2, ExactRealRootBound<Field.Value>.self, &a)
            for bound in [domain.lower, domain.upper] {
                if case .finite(let value) = bound {
                    let law = try polynomials.subtracting(polynomials.variable(axis, using: &a), polynomials.constant(context.field.importing(value,using:&a), using: &a), using: &a)
                    try insert(law, into: &pending, &a)
                }
            }
        }
        try ExactCellAccess.storage(source.variableCount, ExactRealCellProjectionLevel<Base>.self, &a)
        var descending: [ExactRealCellProjectionLevel<Base>] = []
        for axis in (0..<source.variableCount).reversed() {
            var laws: [Polynomial] = []
            for law in pending { try insert(law, into: &laws, &a) }
            let cutLawCount = laws.count
            var witnesses: [ExactRealCellProjectionWitness<Base>] = []
            var offset = 0
            while offset < laws.count {
                let law = laws[offset]; offset += 1
                let d = try polynomials.differentiated(law, in: axis, using: &a)
                try ExactCellAccess.storage(1, ExactRealCellProjectionWitness<Base>.self, &a)
                witnesses.append(.derivative(original: law, result: d, axis: axis))
                try insert(d, into: &laws, &a)
            }
            var lower: [Polynomial] = [], coefficients: [[Polynomial]] = [], families: [[Polynomial]] = []
            try ExactCellAccess.storage(laws.count, [Polynomial].self, &a)
            try ExactCellAccess.storage(laws.count, [Polynomial].self, &a)
            for law in laws {
                let cs = try coefficientVector(law, axis: axis, &a); coefficients.append(cs)
                for degree in cs.indices {
                    try ExactCellAccess.storage(1, ExactRealCellProjectionWitness<Base>.self, &a)
                    witnesses.append(.coefficient(original: law, result: cs[degree], axis: axis, degree: degree))
                    try insert(cs[degree], into: &lower, &a)
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
                            try insert(psc, into: &lower, &a)
                        }
                    }
                    try ExactCellAccess.storage(remainder.termCount, ExactPolynomialTerm<Field.Value>.self, &a)
                    var terms: [ExactPolynomialTerm<Field.Value>] = []
                    for term in remainder.terms {
                        try a.consumeWork(1); if term.powers[axis] != degree { terms.append(term) }
                    }
                    remainder = try polynomials.polynomial(terms: terms, using: &a)
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
                        try insert(psc,into:&lower,&a)
                    }
                } }
            } }
            descending.append(.init(axis:axis,cutLawCount:cutLawCount,laws:laws,coefficients:coefficients,witnesses:witnesses)); pending = lower
        }
        try ExactCellAccess.storage(descending.count, ExactRealCellProjectionLevel<Base>.self, &a)
        return Array(descending.reversed())
    }
}
