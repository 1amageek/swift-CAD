#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

extension ExactRealCellDomain {
    func parentConditions(_ level: ExactRealCellProjectionLevel<Base>, parent: ExactRealCellRecord<Base>,
        _ a: inout ExactCellBorrowedAdmission) throws -> [ExactSign] {
        try ExactCellAccess.storage(level.bindings.count, ExactSign.self, &a)
        var signs: [ExactSign] = []; signs.reserveCapacity(level.bindings.count)
        for binding in level.bindings {
            try a.consumeWork(1)
            let expected: ExactSign
            if let index = binding.lowerLawIndex {
                guard level.axis > 0, parent.sample.coordinates.count == level.axis,
                    parent.projectionSigns.indices.contains(index) else { throw ExactRealCellFailure.invalidCoverage }
                let orientation = try context.field.sign(of: binding.multiplier, using: &a)
                guard orientation != .zero else { throw ExactRealCellFailure.invalidCoverage }
                let raw = parent.projectionSigns[index]
                expected = orientation == .positive ? raw : raw == .positive ? .negative : raw == .negative ? .positive : .zero
            } else {
                for term in binding.polynomial.terms { for power in term.powers {
                    try a.consumeWork(1)
                    guard power == 0 else { throw ExactRealCellFailure.invalidCoverage }
                } }
                expected = try context.field.sign(of: binding.polynomial.terms.first?.coefficient
                    ?? context.field.integer(0, using: &a), using: &a)
            }
            let actual = try parent.sample.field.sign(of: evaluate(binding.polynomial, at: parent.sample, &a), using: &a)
            guard actual == expected else { throw ExactRealCellFailure.invalidCoverage }
            signs.append(expected)
        }
        return signs
    }
    func validateParentConditions(_ level: ExactRealCellProjectionLevel<Base>, stack: ExactRealCellStack<Base>,
        prefix: ExactRealCellSample<Base>, _ a: inout ExactCellBorrowedAdmission) throws {
        guard prefix.coordinates.count == level.axis, stack.axis == level.axis,
            stack.parentConditionSigns.count == level.bindings.count,
            stack.coefficientSigns.count == level.laws.count else { throw ExactRealCellFailure.invalidCoverage }
        for index in level.bindings.indices {
            let actual = try prefix.field.sign(of: evaluate(level.bindings[index].polynomial, at: prefix, &a), using: &a)
            guard actual == stack.parentConditionSigns[index] else { throw ExactRealCellFailure.invalidCoverage }
        }
        for law in level.laws.indices {
            guard stack.coefficientSigns[law].count == level.coefficients[law].count else { throw ExactRealCellFailure.invalidCoverage }
            for degree in level.coefficients[law].indices {
                let actual = try prefix.field.sign(of: evaluate(level.coefficients[law][degree], at: prefix, &a), using: &a)
                guard actual == stack.coefficientSigns[law][degree] else { throw ExactRealCellFailure.invalidCoverage }
            }
        }
    }
    func rootMultiplicity(_ source: ExactRealRootSource<Field>, at root: ExactRealRoot<Field>,
        issuer: ExactRealRootDomain<Field>, _ a: inout ExactCellBorrowedAdmission) throws -> Int {
        let p = issuer.polynomials
        guard let degree = try p.degree(of: source.original, in: 0, using: &a) else { return 0 }
        var law = source, order = 0
        while try issuer.sign(of: law, at: root, using: &a) == .zero {
            guard order < degree else { throw ExactRealCellFailure.invalidCoverage }
            order = try ExactCellAccess.add(order, 1)
            law = try issuer.bind(p.differentiated(law.original, in: 0, using: &a), using: &a)
        }
        return order
    }
    func originalMultiplicities(_ set: ExactRealRootSet<Field>, specialized: [ExactRealRootSource<Field>],
        cutLawCount: Int, _ a: inout ExactCellBorrowedAdmission) throws -> [[Int]] {
        guard cutLawCount >= 0, cutLawCount <= specialized.count else { throw ExactRealCellFailure.invalidCoverage }
        let issuer = try ExactRealRootDomain(retaining: set.source, using: &a)
        try ExactCellAccess.storage(cutLawCount, [Int].self, &a)
        var result: [[Int]] = []; result.reserveCapacity(cutLawCount)
        for index in 0..<cutLawCount {
            try ExactCellAccess.storage(set.roots.count, Int.self, &a)
            var row: [Int] = []; row.reserveCapacity(set.roots.count)
            for root in set.roots {
                row.append(try rootMultiplicity(specialized[index], at: root, issuer: issuer, &a))
            }
            result.append(row)
        }
        return result
    }
    func validateRootCorrespondence(_ set: ExactRealRootSet<Field>, specialized: [ExactRealRootSource<Field>],
        stack: ExactRealCellStack<Base>, _ a: inout ExactCellBorrowedAdmission) throws {
        guard set.roots.count == stack.rootSet.roots.count, specialized.count == stack.effectiveDegrees.count else {
            throw ExactRealCellFailure.invalidCoverage
        }
        let issuer = try ExactRealRootDomain(retaining: set.source, using: &a)
        for index in specialized.indices {
            let degree = try issuer.polynomials.degree(of: specialized[index].original, in: 0, using: &a) ?? -1
            guard degree == stack.effectiveDegrees[index] else { throw ExactRealCellFailure.invalidCoverage }
        }
        for index in stack.rootMultiplicities.indices {
            guard stack.rootMultiplicities[index].count == set.roots.count else { throw ExactRealCellFailure.invalidCoverage }
            for ordinal in set.roots.indices {
                guard try rootMultiplicity(specialized[index], at: set.roots[ordinal], issuer: issuer, &a)
                    == stack.rootMultiplicities[index][ordinal] else { throw ExactRealCellFailure.invalidCoverage }
            }
        }
    }
}
