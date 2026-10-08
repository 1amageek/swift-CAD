#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

extension DefaultExactGeometricRelationResolver {
    func remap<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial, offset: Int,
        into domain: ExactPolynomialDomain<Field>, field: Field, _ a: inout A) throws -> Polynomial {
        guard offset >= 0, try ExactGeometryAccess.add(offset, law.variableCount) <= domain.variableCount else {
            throw ExactGeometricRelationFailure.invalidSourceBinding
        }
        try a.admitDepth(value: law.depth.value, coefficient: law.depth.coefficient)
        try ExactGeometryAccess.storage(law.termCount, ExactPolynomialTerm<Field.Value>.self, &a)
        var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(law.termCount)
        for term in law.terms {
            try ExactGeometryAccess.storage(domain.variableCount, Int.self, &a)
            var powers = Array(repeating: 0, count: domain.variableCount)
            for i in term.powers.indices { try a.consumeWork(1); powers[offset + i] = term.powers[i] }
            terms.append(.init(powers: powers, coefficient: try field.importing(term.coefficient, using: &a)))
        }
        return try domain.polynomial(terms: terms, using: &a)
    }

    func constantMap<A: ExactScalarAdmission & ~Copyable>(_ map: ExactParametricMap<Base>,
        _ a: inout A) throws -> (constant: Bool, proofs: [Polynomial]) {
        let cells = try Cells(retaining: map.original, using: &a), p = cells.polynomials
        let weight = map.original.polynomials[3]
        let capacity = try ExactGeometryAccess.multiply(map.parameterCount, 3)
        try ExactGeometryAccess.storage(capacity, Polynomial.self, &a)
        var proofs: [Polynomial] = []; proofs.reserveCapacity(capacity)
        for axis in 0..<map.parameterCount {
            let dw = try p.differentiated(weight, in: axis, using: &a)
            for coordinate in 0..<3 {
                let h = map.original.polynomials[coordinate]
                let numerator = try p.subtracting(p.multiplying(p.differentiated(h, in: axis, using: &a), weight, using: &a),
                    p.multiplying(h, dw, using: &a), using: &a)
                proofs.append(numerator)
                if try !p.isZero(numerator, using: &a) { return (false, proofs) }
            }
        }
        return (true, proofs)
    }

    func affineInjection<A: ExactScalarAdmission & ~Copyable>(_ map: ExactParametricMap<Base>,
        _ a: inout A) throws -> Polynomial? {
        guard map.parameterCount == 2 else { return nil }
        let cells = try Cells(retaining: map.original, using: &a), p = cells.polynomials
        for term in map.original.polynomials[3].terms {
            for power in term.powers { try a.consumeWork(1); if power != 0 { try a.checkpoint(); return nil } }
        }
        for coordinate in 0..<3 {
            for term in map.original.polynomials[coordinate].terms {
                var degree = 0
                for power in term.powers { try a.consumeWork(1); degree = try ExactGeometryAccess.add(degree, power) }
                if degree > 1 { try a.checkpoint(); return nil }
            }
        }
        // Rank-two affine maps are globally injective under the original nonzero W guard.
        for first in 0..<2 {
            for second in (first + 1)..<3 {
                let x = map.original.polynomials[first], y = map.original.polynomials[second]
                let determinant = try p.subtracting(
                    p.multiplying(p.differentiated(x, in: 0, using: &a), p.differentiated(y, in: 1, using: &a), using: &a),
                    p.multiplying(p.differentiated(x, in: 1, using: &a), p.differentiated(y, in: 0, using: &a), using: &a), using: &a)
                if try !p.isZero(determinant, using: &a) { return determinant }
            }
        }
        try a.checkpoint(); return nil
    }

    /// Each parameter has a nonconstant univariate XYZ coordinate and constant W.
    /// A fixed XYZ gives finitely many roots for each parameter; folds retain every root.
    func finiteFiberMap<A: ExactScalarAdmission & ~Copyable>(_ map: ExactParametricMap<Base>,
        _ a: inout A) throws -> [Polynomial]? {
        guard map.parameterCount == 2 else { return nil }
        let cells = try Cells(retaining: map.original, using: &a), p = cells.polynomials
        for term in map.original.polynomials[3].terms {
            for power in term.powers { try a.consumeWork(1); if power != 0 { return nil } }
        }
        try ExactGeometryAccess.storage(2, Polynomial.self, &a)
        var proofs: [Polynomial] = []; proofs.reserveCapacity(2)
        for axis in 0..<2 {
            var witness: Polynomial? = nil
            for coordinate in 0..<3 {
                let law = map.original.polynomials[coordinate]
                var univariate = true
                for term in law.terms {
                    for other in 0..<2 where other != axis {
                        try a.consumeWork(1); if term.powers[other] != 0 { univariate = false }
                    }
                }
                if !univariate { continue }
                let derivative = try p.differentiated(law, in: axis, using: &a)
                if try !p.isZero(derivative, using: &a) { witness = derivative; break }
            }
            guard let witness else { return nil }; proofs.append(witness)
        }
        return proofs
    }

    /// Exact independence from v and nonconstancy in u identify a rational curve.
    func firstParameterCurve<A: ExactScalarAdmission & ~Copyable>(_ map: ExactParametricMap<Base>,
        _ a: inout A) throws -> [Polynomial]? {
        guard map.parameterCount == 2 else { return nil }
        let cells = try Cells(retaining: map.original, using: &a), p = cells.polynomials
        let weight = map.original.polynomials[3]
        try ExactGeometryAccess.storage(6, Polynomial.self, &a)
        var proofs: [Polynomial] = []; proofs.reserveCapacity(6)
        var nonconstant = false
        for axis in [1, 0] {
            let dw = try p.differentiated(weight, in: axis, using: &a)
            for coordinate in 0..<3 {
                let h = map.original.polynomials[coordinate]
                let d = try p.subtracting(p.multiplying(p.differentiated(h, in: axis, using: &a), weight, using: &a),
                    p.multiplying(h, dw, using: &a), using: &a)
                proofs.append(d)
                if try !p.isZero(d, using: &a) {
                    if axis == 1 { return nil }; nonconstant = true
                }
            }
        }
        return nonconstant ? proofs : nil
    }

    func graphPredicate<A: ExactScalarAdmission & ~Copyable>(_ original: ExactParametricRelationSource<Base>,
        field: Field, _ a: inout A) throws -> ExactRealCellPredicate<Base> {
        let n = try ExactGeometryAccess.add(3, original.predicate.source.variableCount)
        let cells = try Cells(field: field, variableCount: n, using: &a), p = cells.polynomials
        let count = try ExactGeometryAccess.add(original.predicate.source.polynomials.count, 3)
        try ExactGeometryAccess.storage(count, Polynomial.self, &a)
        var laws: [Polynomial] = []; laws.reserveCapacity(count)
        for law in original.predicate.source.polynomials { laws.append(try remap(law, offset: 3, into: p, field: field, &a)) }
        let weight = try remap(original.first.original.polynomials[3], offset: 3, into: p, field: field, &a)
        let start = laws.count
        for axis in 0..<3 {
            let h = try remap(original.first.original.polynomials[axis], offset: 3, into: p, field: field, &a)
            laws.append(try p.subtracting(p.multiplying(p.variable(axis, using: &a), weight, using: &a), h, using: &a))
        }
        let roots = try ExactRealRootDomain(field: field, using: &a)
        let line = try roots.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
        try ExactGeometryAccess.storage(n, ExactRealRootInterval<Field.Value>.self, &a)
        var domains: [ExactRealRootInterval<Field.Value>] = []; domains.reserveCapacity(n)
        for _ in 0..<3 { try a.consumeWork(1); domains.append(line) }
        for domain in original.predicate.source.domains { try a.consumeWork(1); domains.append(domain) }
        let source = try cells.bind(polynomials: laws, domains: domains, using: &a)
        try ExactGeometryAccess.storage(try ExactGeometryAccess.add(original.predicate.instructions.count, 6), ExactRealCellInstruction.self, &a)
        var instructions: [ExactRealCellInstruction] = []; instructions.reserveCapacity(original.predicate.instructions.count + 6)
        for instruction in original.predicate.instructions { try a.consumeWork(1); instructions.append(instruction) }
        for i in start..<laws.count { instructions.append(.sign(polynomial: i, relation: .equal)); instructions.append(.and) }
        return try cells.predicate(instructions: instructions, for: source, using: &a)
    }
}
