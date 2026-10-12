#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

extension ExactParametricRelationDomain: ExactParametricGraphConstructing {
    public func graph<A: ExactScalarAdmission & ~Copyable>(from predicate: borrowing ExactRealCellPredicate<Base>,
        parameterCount: Int, using a: inout A) throws(ExactParametricRelationFailure) -> ExactParametricGraph<Base> {
        do {
            try a.checkpoint(); try a.consumeWork(1)
            guard (1...2).contains(parameterCount), parameterCount <= predicate.source.variableCount,
                predicate.source.polynomials.count >= 4 else { throw ExactParametricRelationFailure.invalidMap }
            let cells = try Cells(retaining: predicate.source, using: &a)
            _ = try cells.coefficientField(of: predicate.source, using: &a)
            try a.admitDepth(value: predicate.depth.value, coefficient: predicate.depth.coefficient)
            try storage(1, ExactParametricGraph<Base>.self, &a)
            let graph = ExactParametricGraph(predicate: copy predicate, parameterCount: parameterCount)
            try a.checkpoint(); return graph
        } catch { throw .init(error) }
    }

    public func compile<A: ExactScalarAdmission & ~Copyable>(kind: ExactParametricRelationKind,
        first: borrowing ExactParametricGraph<Base>, second: borrowing ExactParametricGraph<Base>,
        using a: inout A) throws(ExactParametricRelationFailure) -> ExactParametricGraphRelationSource<Base> {
        do {
            try a.checkpoint(); try a.consumeWork(1)
            let firstCount = kind == .curveSurface ? 1 : 2
            guard first.parameterCount == firstCount, second.parameterCount == 2 else { throw ExactParametricRelationFailure.invalidKind }
            let sum = first.variableCount.addingReportingOverflow(second.variableCount)
            guard !sum.overflow else { throw ExactParametricRelationFailure.countOverflow }
            let n = sum.partialValue, p = first.parameterCount + second.parameterCount
            let lc = try Cells(retaining: first.predicate.source, using: &a)
            let rc = try Cells(retaining: second.predicate.source, using: &a)
            let field = try lc.coefficientField(of: first.predicate.source, using: &a)
            let rf = try rc.coefficientField(of: second.predicate.source, using: &a)
            _ = try field.importing(rf.integer(0, using: &a), using: &a)
            try a.admitDepth(value: first.predicate.depth.value, coefficient: first.predicate.depth.coefficient)
            try a.admitDepth(value: second.predicate.depth.value, coefficient: second.predicate.depth.coefficient)
            let cells = try Cells(field: field, variableCount: n, using: &a), ring = cells.polynomials
            try storage(first.variableCount, Int.self, &a); try storage(second.variableCount, Int.self, &a)
            var leftMap: [Int] = [], rightMap: [Int] = []
            leftMap.reserveCapacity(first.variableCount); rightMap.reserveCapacity(second.variableCount)
            for i in 0..<first.variableCount { try a.consumeWork(1); leftMap.append(i < first.parameterCount ? i : p+i-first.parameterCount) }
            for i in 0..<second.variableCount {
                try a.consumeWork(1)
                rightMap.append(i < second.parameterCount ? first.parameterCount+i : first.variableCount+second.parameterCount+i-second.parameterCount)
            }
            let left = try graphLaws(first.predicate.source.polynomials, map: leftMap, to: ring, field: field, &a)
            let right = try graphLaws(second.predicate.source.polynomials, map: rightMap, to: ring, field: field, &a)
            let rawSize = left.count.addingReportingOverflow(right.count)
            guard !rawSize.overflow else { throw ExactParametricRelationFailure.countOverflow }
            let size = rawSize.partialValue.addingReportingOverflow(5)
            guard !size.overflow else { throw ExactParametricRelationFailure.countOverflow }
            try storage(size.partialValue, Polynomial.self, &a)
            var laws: [Polynomial] = []; laws.reserveCapacity(size.partialValue)
            let inputSize = first.predicate.instructions.count.addingReportingOverflow(second.predicate.instructions.count)
            guard !inputSize.overflow else { throw ExactParametricRelationFailure.countOverflow }
            let total = inputSize.partialValue.addingReportingOverflow(11)
            guard !total.overflow else { throw ExactParametricRelationFailure.countOverflow }
            try storage(total.partialValue, ExactRealCellInstruction.self, &a)
            try storage(left.count, Int.self, &a); try storage(right.count, Int.self, &a)
            try a.consumeWork(rawSize.partialValue)
            var leftSlots = [Int](repeating:-1,count:left.count), rightSlots = [Int](repeating:-1,count:right.count)
            var instructions: [ExactRealCellInstruction] = []; instructions.reserveCapacity(total.partialValue)
            // XYZ/W are position expressions, not sign-invariance requests. Only
            // atoms referenced by the predicates, W guards and equality are solved.
            for side in 0..<2 {
                let predicate = side == 0 ? first.predicate : second.predicate
                for instruction in predicate.instructions {
                    try a.consumeWork(1)
                    switch instruction {
                    case .sign(let index, let relation):
                        guard index >= 0, index < predicate.source.polynomials.count else { throw ExactParametricRelationFailure.invalidEvidence }
                        var slot = side == 0 ? leftSlots[index] : rightSlots[index]
                        if slot == -1 {
                            slot = laws.count; laws.append(side == 0 ? left[index] : right[index])
                            if side == 0 { leftSlots[index] = slot } else { rightSlots[index] = slot }
                        }
                        instructions.append(.sign(polynomial:slot,relation:relation))
                    default: instructions.append(instruction)
                    }
                }
                if side == 1 { instructions.append(.and) }
            }
            for side in 0..<2 {
                try a.consumeWork(1)
                if side == 0 && leftSlots[3] == -1 { leftSlots[3] = laws.count; laws.append(left[3]) }
                if side == 1 && rightSlots[3] == -1 { rightSlots[3] = laws.count; laws.append(right[3]) }
            }
            let equalityOffset = laws.count
            try storage(3, Polynomial.self, &a)
            try storage(6, ExactParametricGuardDivision<Base>.self, &a)
            var remainders: [ExactParametricGuardRemainder<Base>] = []
            var raw: [Polynomial] = []; raw.reserveCapacity(3)
            var divisions: [ExactParametricGuardDivision<Base>] = []; divisions.reserveCapacity(6)
            for axis in 0..<3 {
                try a.consumeWork(1)
                var equation = try ring.subtracting(ring.multiplying(left[axis], right[3], using: &a),
                    ring.multiplying(right[axis], left[3], using: &a), using: &a)
                raw.append(equation)
                // The retained W guards prove each exact division is equivalent on
                // the selected graph, just as in the existing rational-map compiler.
                for guardIndex in 0..<2 {
                    let guardLaw = guardIndex == 0 ? left[3] : right[3]
                    var nonconstant = false
                    for term in guardLaw.terms {
                        try a.consumeWork(1)
                        for power in term.powers { try a.consumeWork(1); if power > 0 { nonconstant = true } }
                    }
                    if !nonconstant { continue }
                    if try ring.isZero(equation,using:&a) { continue }
                    let division = try ring.divided(equation,by:guardLaw,using:&a)
                    if try ring.isZero(division.remainder,using:&a) {
                        divisions.append(.init(equationIndex:axis,guardIndex:guardIndex,dividend:equation,division:division))
                        equation = division.quotient
                    }
                }
                equation = try graphRemainder(equation,equationIndex:axis,first:copy first,second:copy second,
                    left:left,right:right,leftSlots:leftSlots,rightSlots:rightSlots,ring:ring,proofs:&remainders,&a)
                laws.append(equation)
            }
            try storage(n, ExactRealRootInterval<Field.Value>.self, &a)
            let roots = try ExactRealRootDomain(field: field, using: &a)
            let line = try roots.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
            var domains = [ExactRealRootInterval<Field.Value>](repeating: line, count: n)
            for i in leftMap.indices { try a.consumeWork(1); domains[leftMap[i]] = first.predicate.source.domains[i] }
            for i in rightMap.indices { try a.consumeWork(1); domains[rightMap[i]] = second.predicate.source.domains[i] }
            let source = try cells.bind(polynomials: laws, domains: domains, using: &a)
            instructions.append(.sign(polynomial:leftSlots[3],relation:.notEqual)); instructions.append(.and)
            instructions.append(.sign(polynomial:rightSlots[3],relation:.notEqual)); instructions.append(.and)
            for i in 0..<3 { instructions.append(.sign(polynomial: equalityOffset+i, relation: .equal)); instructions.append(.and) }
            let predicate = try cells.predicate(instructions: instructions, for: source, using: &a)
            var depth = try graphDepth(first.predicate.depth,second.predicate.depth)
            depth = try graphDepth(depth,predicate.depth)
            for law in raw { try a.consumeWork(1); depth = try graphDepth(depth,law.depth) }
            for proof in divisions {
                try a.consumeWork(1)
                depth = try graphDepth(depth,proof.dividend.depth)
                depth = try graphDepth(depth,proof.division.quotient.depth)
                depth = try graphDepth(depth,proof.division.remainder.depth)
            }
            for proof in remainders {
                try a.consumeWork(1)
                depth = try graphDepth(depth,proof.equation.depth)
                depth = try graphDepth(depth,proof.dividend.depth)
                depth = try graphDepth(depth,proof.division.quotient.depth)
                depth = try graphDepth(depth,proof.division.remainder.depth)
            }
            try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
            try storage(1, ExactParametricGraphRelationSource<Base>.self, &a)
            let result = ExactParametricGraphRelationSource(kind: kind, first: copy first, second: copy second,
                firstCoordinates: leftMap, secondCoordinates: rightMap, firstLawIndices:leftSlots, secondLawIndices:rightSlots,
                equationIndices:equalityOffset..<(equalityOffset+3), rawEquations: raw, guardDivisions: divisions, guardRemainders: remainders, predicate: predicate, depth: depth)
            try a.checkpoint(); return result
        } catch { throw .init(error) }
    }

    func graphDepth(_ first: ExactScalarDepth, _ second: ExactScalarDepth) throws(ExactScalarFailure) -> ExactScalarDepth {
        try .init(value:max(first.value,second.value),coefficient:max(first.coefficient,second.coefficient))
    }

    private func graphLaws<A: ExactScalarAdmission & ~Copyable>(_ laws: [Polynomial], map: [Int],
        to ring: ExactPolynomialDomain<Field>, field: Field, _ a: inout A) throws -> [Polynomial] {
        try storage(laws.count, Polynomial.self, &a)
        var result: [Polynomial] = []; result.reserveCapacity(laws.count)
        for law in laws {
            try a.consumeWork(1)
            try a.admitDepth(value: law.depth.value, coefficient: law.depth.coefficient)
            try storage(law.termCount, ExactPolynomialTerm<Field.Value>.self, &a)
            var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(law.termCount)
            for term in law.terms {
                try a.consumeWork(1); try storage(ring.variableCount, Int.self, &a)
                var powers = [Int](repeating: 0, count: ring.variableCount)
                for i in map.indices { try a.consumeWork(1); powers[map[i]] = term.powers[i] }
                terms.append(.init(powers: powers, coefficient: try field.importing(term.coefficient, using: &a)))
            }
            result.append(try ring.polynomial(terms: terms, using: &a))
        }
        return result
    }
}

extension ExactParametricRelationDomain: ExactParametricGraphResolving where Topology: ExactRealProjectionProducing {
    public func resolve<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactParametricGraphRelationSource<Base>,
        cellLimits: ExactRealCellLimits, topologyLimits: ExactRealTopologyLimits,
        using a: inout A) throws(ExactParametricRelationFailure) -> ExactParametricGraphRelation<Base> {
        do {
            try a.checkpoint()
            try a.admitDepth(value:source.depth.value,coefficient:source.depth.coefficient)
            let cells = try Cells(retaining: source.predicate.source, using: &a)
            let partition = try cells.decompose(source.predicate.source, limits: cellLimits, using: &a)
            let selection = try cells.select(partition, matching: source.predicate, using: &a)
            let projection = try topology.project(selection, retainingPrefix: source.parameterCount,
                cellLimits: cellLimits, topologyLimits: topologyLimits, using: &a)
            try storage(1, ExactParametricGraphRelation<Base>.self, &a)
            let result = ExactParametricGraphRelation(original: copy source, projection: projection, depth:try graphDepth(source.depth,projection.depth))
            try a.checkpoint(); return result
        } catch { throw .init(error) }
    }
}
