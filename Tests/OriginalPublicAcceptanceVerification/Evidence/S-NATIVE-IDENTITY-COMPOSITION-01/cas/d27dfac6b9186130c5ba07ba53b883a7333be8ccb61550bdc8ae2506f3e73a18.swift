#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain: ExactRealCellPullbackResolving {
    public func refinePullback<A: ExactScalarAdmission & ~Copyable>(
        of source: borrowing ExactRealCellSelection<Base>,
        onto target: borrowing ExactRealCellPredicate<Base>, coordinateMap: borrowing [Int],
        cellLimits: ExactRealCellLimits, topologyLimits: ExactRealTopologyLimits,
        using admission: inout A
    ) throws(ExactRealTopologyFailure) -> ExactRealCellPullback<Base> {
        do {
            try admission.checkpoint()
            var counts = ExactTopologyCounts(depth: source.depth)
            try counts.retain(target.depth, &admission)
            let n = target.source.variableCount
            guard coordinateMap.count == source.partition.source.variableCount else {
                throw ExactRealTopologyFailure.invalidDefinition
            }
            try ExactTopologyAccess.storage(n, Bool.self, &admission)
            var occupied = Array(repeating: false, count: n)
            try ExactTopologyAccess.storage(coordinateMap.count, Int.self, &admission)
            var mapping: [Int] = []; mapping.reserveCapacity(coordinateMap.count)
            for i in coordinateMap.indices {
                try admission.consumeWork(1)
                let slot = coordinateMap[i]
                guard slot >= 0, slot < n, !occupied[slot] else { throw ExactRealTopologyFailure.invalidDefinition }
                occupied[slot] = true; mapping.append(slot)
            }
            let sc = try Cells(retaining: source.partition.source, using: &admission)
            let tc = try Cells(retaining: target.source, using: &admission)
            let field = try sc.coefficientField(of: source.partition.source, using: &admission)
            let targetField = try tc.coefficientField(of: target.source, using: &admission)
            // Validate even unrelated zero-polynomial fields before any empty success.
            _ = try field.importing(targetField.integer(0, using: &admission), using: &admission)
            try ExactTopologyAccess.storage(source.cells.count, ExactRealCellDefinition<Base>.self, &admission)
            var definitions: [ExactRealCellDefinition<Base>] = []; definitions.reserveCapacity(source.cells.count)
            for cell in source.cells {
                let d = try sc.definition(of: cell, in: source.partition, using: &admission)
                try counts.retain(d.depth, &admission)
                definitions.append(d)
            }
            // Exact Thom ordering eliminates boundary witnesses before decomposition.
            var f = try formula(field: field, free: n, quantifiers: [], &admission)
            let identity = try map(n, &admission)
            // Necessary remapping materializes expanded power vectors once per law.
            let atomOffset = f.atoms.count
            for law in target.source.polynomials {
                try ExactTopologyAccess.storage(ExactTopologyAccess.add(f.atoms.count, 1), Polynomial.self, &admission)
                f.atoms.append(try f.remap(law, identity, &admission))
            }
            for instruction in target.instructions {
                switch instruction {
                case .sign(let index, let relation):
                    guard index >= 0, index < target.source.polynomials.count else { throw ExactRealTopologyFailure.invalidFormula }
                    try f.instruction(.sign(polynomial: try ExactTopologyAccess.add(atomOffset, index), relation: relation), &admission)
                default: try f.instruction(instruction, &admission)
                }
            }
            for axis in 0..<n {
                let domain = target.source.domains[axis]
                for isLower in [true, false] {
                    let endpoint = isLower ? domain.lower : domain.upper
                    if case .finite(let value) = endpoint {
                        let delta = try f.polynomials.subtracting(f.polynomials.variable(axis, using: &admission),
                            f.polynomials.constant(value, using: &admission), using: &admission)
                        let inclusive = isLower ? domain.includesLower : domain.includesUpper
                        let relation: ExactRealCellSignRelation = isLower
                            ? (inclusive ? .greaterOrEqual : .greater) : (inclusive ? .lessOrEqual : .less)
                        try f.atom(delta, relation, &admission); try f.instruction(.and, &admission)
                    }
                }
                if domain.isEmpty { try f.instruction(.literal(false), &admission); try f.instruction(.and, &admission) }
            }
            try f.instruction(.literal(false), &admission)
            try ExactTopologyAccess.storage(definitions.count, Range<Int>.self, &admission)
            var ranges: [Range<Int>] = []; ranges.reserveCapacity(definitions.count)
            var witness = n
            for d in definitions {
                let start = f.instructions.count
                try f.cell(d, map: mapping, witness: &witness, weak: false, sectorOrderByThom: true, &admission)
                ranges.append(start..<f.instructions.count)
                try f.instruction(.or, &admission)
            }
            try f.instruction(.and, &admission)
            guard witness == f.polynomials.variableCount else { throw ExactRealTopologyFailure.invalidFormula }
            // Label ranges share one exact quantifier-free partition. Auxiliary
            // root witnesses have been eliminated by the retained Thom identities.
            // Intern exact repeated laws once before pairwise projection. Label programs
            // retain their instruction ranges and reference the same canonical sign atoms.
            try ExactTopologyAccess.storage(f.atoms.count, Int.self, &admission)
            try ExactTopologyAccess.storage(f.atoms.count, Polynomial.self, &admission)
            var atomMap: [Int] = []; atomMap.reserveCapacity(f.atoms.count)
            var unique: [Polynomial] = []; unique.reserveCapacity(f.atoms.count)
            for atom in f.atoms {
                var found: Int? = nil
                for index in unique.indices {
                    try admission.consumeWork(1)
                    if try f.polynomials.equals(atom, unique[index], using: &admission) { found = index; break }
                }
                if let found { atomMap.append(found) }
                else { atomMap.append(unique.count); unique.append(atom) }
            }
            for index in f.instructions.indices {
                try admission.consumeWork(1)
                if case .sign(let ordinal, let relation) = f.instructions[index] {
                    guard ordinal >= 0, ordinal < atomMap.count else { throw ExactRealTopologyFailure.invalidFormula }
                    f.instructions[index] = .sign(polynomial: atomMap[ordinal], relation: relation)
                }
            }
            f.atoms = unique
            let bounded = try ExactRealTopologyLimits(
                maximumGeneratedCells: min(cellLimits.maximumStoredCells, topologyLimits.maximumGeneratedCells),
                maximumRootsPerStack: min(cellLimits.maximumRootsPerStack, topologyLimits.maximumRootsPerStack),
                maximumClosures: topologyLimits.maximumClosures,
                maximumAttachmentPieces: topologyLimits.maximumAttachmentPieces,
                maximumComponents: topologyLimits.maximumComponents)
            let targetDomains = target.source.domains.contains { $0.isEmpty } ? nil : target.source.domains
            let region = try reduce(f, limits: bounded, counts: &counts, domains: targetDomains, &admission)
            try ExactTopologyAccess.storage(region.cells.count, Int.self, &admission)
            var labels = Array(repeating: -1, count: region.cells.count)
            try ExactTopologyAccess.storage(region.decisions.count, Bool.self, &admission)
            var truthValues = Array(repeating: false, count: region.decisions.count)
            try ExactTopologyAccess.storage(f.instructions.count, Bool.self, &admission)
            var stack: [Bool] = []; stack.reserveCapacity(f.instructions.count)
            for ordinal in ranges.indices {
                for index in region.decisions.indices.reversed() {
                    try admission.consumeWork(1)
                    let node = region.decisions[index]
                    let count = (node.cell.axis ?? -1) + 1
                    if count == f.polynomials.variableCount {
                        stack.removeAll(keepingCapacity: true)
                        for offset in ranges[ordinal] {
                            try admission.consumeWork(1)
                            switch f.instructions[offset] {
                            case .literal(let value): stack.append(value)
                            case .sign(let law, let relation):
                                guard law >= 0, law < node.cell.signs.count else { throw ExactRealTopologyFailure.invalidFormula }
                                stack.append(ExactTopologyAccess.accepts(node.cell.signs[law], relation))
                            case .not:
                                guard let value = stack.popLast() else { throw ExactRealTopologyFailure.invalidFormula }; stack.append(!value)
                            case .and, .or:
                                guard let right = stack.popLast(), let left = stack.popLast() else { throw ExactRealTopologyFailure.invalidFormula }
                                if case .and = f.instructions[offset] { stack.append(left && right) } else { stack.append(left || right) }
                            }
                        }
                        guard stack.count == 1 else { throw ExactRealTopologyFailure.invalidFormula }
                        truthValues[index] = stack[0]
                    } else if count >= n {
                        guard !node.children.isEmpty else { throw ExactRealTopologyFailure.invalidCoverage }
                        var value = false
                        for child in node.children { try admission.consumeWork(1); value = value || truthValues[child] }
                        truthValues[index] = value
                    }
                }
                var freeIndex = 0
                for index in region.decisions.indices {
                    try admission.consumeWork(1)
                    if (region.decisions[index].cell.axis ?? -1) + 1 != n { continue }
                    guard freeIndex < labels.count, region.cells[freeIndex] == region.decisions[index].cell else {
                        throw ExactRealTopologyFailure.invalidCoverage
                    }
                    if region.included[freeIndex] && truthValues[index] {
                        guard labels[freeIndex] == -1 else { throw ExactRealTopologyFailure.invalidCoverage }
                        labels[freeIndex] = ordinal
                    }
                    freeIndex += 1
                }
                guard freeIndex == labels.count else { throw ExactRealTopologyFailure.invalidCoverage }
            }
            for index in labels.indices {
                try admission.consumeWork(1)
                guard region.included[index] == (labels[index] >= 0) else { throw ExactRealTopologyFailure.invalidCoverage }
            }
            try ExactTopologyAccess.storage(1, ExactRealCellPullback<Base>.self, &admission)
            let result = ExactRealCellPullback(source: copy source, target: copy target,
                coordinateMap: mapping, region: region, sourceCellOrdinals: labels, labelInstructionRanges: ranges)
            try admission.checkpoint()
            return result
        } catch { throw .preserving(error) }
    }
}
