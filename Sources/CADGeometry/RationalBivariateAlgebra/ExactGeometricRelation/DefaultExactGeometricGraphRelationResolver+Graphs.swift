#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

extension DefaultExactGeometricGraphRelationResolver {
    func remap<A: ExactScalarAdmission & ~Copyable>(_ law: Polynomial, placement: [Int],
        into ring: ExactPolynomialDomain<Field>, field: Field, _ a: inout A) throws -> Polynomial {
        guard law.variableCount == placement.count else { throw ExactGeometricRelationFailure.invalidSourceBinding }
        try ExactGeometryAccess.storage(law.termCount, ExactPolynomialTerm<Field.Value>.self, &a)
        var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(law.termCount)
        for term in law.terms {
            try ExactGeometryAccess.storage(ring.variableCount, Int.self, &a)
            var powers = Array(repeating: 0, count: ring.variableCount)
            for i in placement.indices {
                try a.consumeWork(1)
                if term.powers[i] == 0 { continue }
                guard placement[i] >= 0, placement[i] < ring.variableCount else { throw ExactGeometricRelationFailure.invalidSourceBinding }
                powers[placement[i]] = term.powers[i]
            }
            terms.append(.init(powers: powers, coefficient: try field.importing(term.coefficient, using: &a)))
        }
        return try ring.polynomial(terms: terms, using: &a)
    }
    func parameterPosition<A: ExactScalarAdmission & ~Copyable>(_ graph: ExactParametricGraph<Base>, _ a: inout A) throws -> Bool {
        for index in 0..<4 {
            for term in graph.predicate.source.polynomials[index].terms {
                for variable in graph.parameterCount..<graph.variableCount {
                    try a.consumeWork(1); if term.powers[variable] != 0 { return false }
                }
            }
        }
        return true
    }
    func graphPredicate<A: ExactScalarAdmission & ~Copyable>(_ relation: ExactParametricGraphRelation<Base>, parameterOnly: Bool, second: Bool,
        field: Field, _ a: inout A) throws -> ExactRealCellPredicate<Base> {
        let original = relation.original
        let base = parameterOnly ? relation.selection.predicate : original.predicate
        let anchor = second ? original.second : original.first
        let anchorCoordinates = second ? original.secondCoordinates : original.firstCoordinates
        let n = try ExactGeometryAccess.add(base.source.variableCount, 3)
        let cells = try Cells(field: field, variableCount: n, using: &a), ring = cells.polynomials
        try ExactGeometryAccess.storage(n - 3, Int.self, &a)
        var placement: [Int] = []; placement.reserveCapacity(n - 3)
        for i in 3..<n { try a.consumeWork(1); placement.append(i) }
        let capacity = try ExactGeometryAccess.add(base.source.polynomials.count, 3)
        try ExactGeometryAccess.storage(capacity, Polynomial.self, &a)
        var laws: [Polynomial] = []; laws.reserveCapacity(capacity)
        for law in base.source.polynomials { laws.append(try remap(law, placement: placement, into: ring, field: field, &a)) }
        try ExactGeometryAccess.storage(anchorCoordinates.count, Int.self, &a)
        var sourcePlacement: [Int] = []; sourcePlacement.reserveCapacity(anchorCoordinates.count)
        for coordinate in anchorCoordinates { try a.consumeWork(1); sourcePlacement.append(coordinate + 3) }
        let position = anchor.predicate.source.polynomials
        let weight = try remap(position[3], placement: sourcePlacement, into: ring, field: field, &a)
        let start = laws.count
        for axis in 0..<3 {
            let h = try remap(position[axis], placement: sourcePlacement, into: ring, field: field, &a)
            laws.append(try ring.subtracting(ring.multiplying(ring.variable(axis, using: &a), weight, using: &a), h, using: &a))
        }
        let roots = try ExactRealRootDomain(field: field, using: &a)
        let line = try roots.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
        try ExactGeometryAccess.storage(n, ExactRealRootInterval<Field.Value>.self, &a)
        var domains: [ExactRealRootInterval<Field.Value>] = []; domains.reserveCapacity(n)
        for _ in 0..<3 { try a.consumeWork(1); domains.append(line) }
        for domain in base.source.domains { try a.consumeWork(1); domains.append(domain) }
        let source = try cells.bind(polynomials: laws, domains: domains, using: &a)
        try ExactGeometryAccess.storage(try ExactGeometryAccess.add(base.instructions.count, 6), ExactRealCellInstruction.self, &a)
        var instructions: [ExactRealCellInstruction] = []; instructions.reserveCapacity(base.instructions.count + 6)
        for instruction in base.instructions { try a.consumeWork(1); instructions.append(instruction) }
        for i in start..<laws.count { instructions.append(.sign(polynomial: i, relation: .equal)); instructions.append(.and) }
        return try cells.predicate(instructions: instructions, for: source, using: &a)
    }
}
