#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

extension ExactParametricRelationDomain: ExactParametricRelationConstructing {
    public func map<A: ExactScalarAdmission & ~Copyable>(from source: borrowing ExactRealCellSource<Base>,
        using admission: inout A) throws(ExactParametricRelationFailure) -> ExactParametricMap<Base> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1)
            guard (1...2).contains(source.variableCount), source.polynomials.count == 4 else {
                throw ExactParametricRelationFailure.invalidMap
            }
            let cells = try Cells(retaining: source, using: &admission)
            _ = try cells.coefficientField(of: source, using: &admission)
            try storage(1, ExactParametricMap<Base>.self, &admission)
            let result = ExactParametricMap(original: copy source)
            try admission.checkpoint()
            return result
        } catch { throw .init(error) }
    }

    public func compile<A: ExactScalarAdmission & ~Copyable>(kind: ExactParametricRelationKind,
        first: borrowing ExactParametricMap<Base>, second: borrowing ExactParametricMap<Base>,
        using admission: inout A) throws(ExactParametricRelationFailure) -> ExactParametricRelationSource<Base> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1)
            let expectedFirst: Int
            switch kind { case .curveSurface: expectedFirst = 1; case .surfaceSurface: expectedFirst = 2 }
            guard first.parameterCount == expectedFirst, second.parameterCount == 2 else {
                throw ExactParametricRelationFailure.invalidKind
            }
            let n = first.parameterCount + second.parameterCount // Both counts are issued in 1...2.
            let firstCells = try Cells(retaining: first.original, using: &admission)
            let secondCells = try Cells(retaining: second.original, using: &admission)
            let field = try firstCells.coefficientField(of: first.original, using: &admission)
            let secondField = try secondCells.coefficientField(of: second.original, using: &admission)
            // Even an all-zero map must retain the original coefficient-family policy.
            _ = try field.importing(secondField.integer(0, using: &admission), using: &admission)
            let cells = try Cells(field: field, variableCount: n, using: &admission)
            let polynomials = cells.polynomials
            try storage(4, Polynomial.self, &admission)
            try storage(4, Polynomial.self, &admission)
            var left: [Polynomial] = [], right: [Polynomial] = []
            left.reserveCapacity(4); right.reserveCapacity(4)
            for index in 0..<4 {
                try admission.consumeWork(1)
                left.append(try remap(first.original.polynomials[index], offset: 0, to: polynomials, field: field, using: &admission))
                right.append(try remap(second.original.polynomials[index], offset: first.parameterCount, to: polynomials, field: field, using: &admission))
            }
            try storage(3, Polynomial.self, &admission)
            var raw: [Polynomial] = []; raw.reserveCapacity(3)
            for index in 0..<3 {
                try admission.consumeWork(1)
                raw.append(try polynomials.subtracting(polynomials.multiplying(left[index], right[3], using: &admission),
                    polynomials.multiplying(right[index], left[3], using: &admission), using: &admission))
            }
            try storage(5, Polynomial.self, &admission)
            try storage(6, ExactParametricGuardDivision<Base>.self, &admission)
            var laws: [Polynomial] = []; laws.reserveCapacity(5)
            var divisions: [ExactParametricGuardDivision<Base>] = []; divisions.reserveCapacity(6)
            for index in 0..<3 {
                try admission.consumeWork(1)
                var equation = raw[index]
                for guardIndex in 0..<2 {
                    try admission.consumeWork(1)
                    let guardLaw = guardIndex == 0 ? left[3] : right[3]
                    var nonconstant = false
                    for term in guardLaw.terms {
                        try admission.consumeWork(1)
                        for power in term.powers {
                            try admission.consumeWork(1)
                            if power > 0 { nonconstant = true }
                        }
                    }
                    if !nonconstant { continue }
                    if try polynomials.isZero(equation, using: &admission) { continue }
                    let division = try polynomials.divided(equation, by: guardLaw, using: &admission)
                    if try polynomials.isZero(division.remainder, using: &admission) {
                        divisions.append(.init(equationIndex: index, guardIndex: guardIndex, dividend: equation, division: division))
                        equation = division.quotient
                    }
                }
                laws.append(equation)
            }
            laws.append(left[3]); laws.append(right[3])
            try storage(n, ExactRealRootInterval<Field.Value>.self, &admission)
            var domains: [ExactRealRootInterval<Field.Value>] = []; domains.reserveCapacity(n)
            for domain in first.original.domains { try admission.consumeWork(1); domains.append(domain) }
            for domain in second.original.domains { try admission.consumeWork(1); domains.append(domain) }
            let source = try cells.bind(polynomials: laws, domains: domains, using: &admission)
            try storage(9, ExactRealCellInstruction.self, &admission)
            var instructions: [ExactRealCellInstruction] = []; instructions.reserveCapacity(9)
            for index in 0..<5 {
                try admission.consumeWork(1)
                instructions.append(.sign(polynomial: index, relation: index < 3 ? .equal : .notEqual))
                if index > 0 { instructions.append(.and) }
            }
            let predicate = try cells.predicate(instructions: instructions, for: source, using: &admission)
            try storage(1, ExactParametricRelationSource<Base>.self, &admission)
            let result = ExactParametricRelationSource(kind: kind, first: copy first, second: copy second, rawEquations: raw, guardDivisions: divisions, predicate: predicate)
            try admission.checkpoint()
            return result
        } catch { throw .init(error) }
    }
}
