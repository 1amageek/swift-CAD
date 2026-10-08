#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain {
    /// One complete affine refinement retains partial attachments to unsplit targets.
    /// Exact factor identity and closed-box eligibility are established before solving.
    func affineFactorIncidence<A: ExactScalarAdmission & ~Copyable>(
        _ selection: borrowing ExactRealCellSelection<Base>, limits: ExactRealTopologyLimits,
        counts: inout ExactTopologyCounts, _ a: inout A
    ) throws -> ExactRealIncidence<Base>? {
        let n = selection.cells.count, source = selection.partition.source
        guard n > 1, try closedBox(source, &a) else { return nil }
        let provider = try Cells(retaining: source, using: &a)
        try ExactTopologyAccess.storage(n, ExactRealCellDefinition<Base>.self, &a)
        try ExactTopologyAccess.storage(n, [ExactRealTopologyFactor<Base>].self, &a)
        var definitions: [ExactRealCellDefinition<Base>] = [], factors: [[ExactRealTopologyFactor<Base>]] = []
        definitions.reserveCapacity(n); factors.reserveCapacity(n)
        var needsRefinement = false
        for cell in selection.cells {
            let d = try provider.definition(of: cell, in: selection.partition, using: &a)
            let fs = try certifiedFactors(d, &a)
            guard try affine(d, through: d.coordinateCount, factors: fs, &a) else { return nil }
            try counts.retain(d.depth, &a)
            for f in fs { try counts.retain(f.factor.depth, &a); try counts.retain(f.quotient.depth, &a) }
            needsRefinement = needsRefinement || !fs.isEmpty
            definitions.append(d); factors.append(fs)
        }
        guard needsRefinement else { return nil }
        counts.closures = try ExactTopologyAccess.add(counts.closures, n)
        guard counts.closures <= limits.maximumClosures else { throw ExactRealTopologyFailure.closureLimit }
        var f = try formula(field: definitions[0].coefficientField, free: source.variableCount, quantifiers: [], &a)
        let slots = try map(source.variableCount, &a)
        try ExactTopologyAccess.storage(n, Range<Int>.self, &a)
        try ExactTopologyAccess.storage(n, Range<Int>.self, &a)
        var closed: [Range<Int>] = [], strict: [Range<Int>] = []
        closed.reserveCapacity(n); strict.reserveCapacity(n)
        try f.instruction(.literal(false), &a)
        var witness = source.variableCount
        for weak in [true, false] {
            for i in definitions.indices {
                let start = f.instructions.count
                try f.cell(definitions[i], map: slots, witness: &witness, weak: weak, factors: factors[i], &a)
                let range = start..<f.instructions.count
                if weak { closed.append(range) } else { strict.append(range) }
                try f.instruction(.or, &a)
            }
        }
        guard witness == source.variableCount else { throw ExactRealTopologyFailure.invalidFormula }
        let common = try reduce(f, limits: limits, counts: &counts, domains: source.domains, &a)
        try ExactTopologyAccess.storage(n, [Bool].self, &a)
        try ExactTopologyAccess.storage(n, [Bool].self, &a)
        var closureMasks: [[Bool]] = [], targetMasks: [[Bool]] = []
        closureMasks.reserveCapacity(n); targetMasks.reserveCapacity(n)
        for i in 0..<n {
            try ExactTopologyAccess.storage(common.cells.count, Bool.self, &a)
            try ExactTopologyAccess.storage(common.cells.count, Bool.self, &a)
            try ExactTopologyAccess.storage(closed[i].count, ExactRealCellInstruction.self, &a)
            try ExactTopologyAccess.storage(strict[i].count, ExactRealCellInstruction.self, &a)
            let c = Array(f.instructions[closed[i]]), t = Array(f.instructions[strict[i]])
            var cm: [Bool] = [], tm: [Bool] = []
            cm.reserveCapacity(common.cells.count); tm.reserveCapacity(common.cells.count)
            for cell in common.cells {
                cm.append(try truth(c, signs: cell.signs, &a)); tm.append(try truth(t, signs: cell.signs, &a))
            }
            guard tm.contains(true) else { throw ExactRealTopologyFailure.invalidCoverage }
            closureMasks.append(cm); targetMasks.append(tm)
        }
        // Strict cells are disjoint. Complete sign decomposition proves their labels.
        for k in common.cells.indices {
            var labels = 0
            for i in 0..<n { try a.consumeWork(1); if targetMasks[i][k] { labels += 1 } }
            guard labels <= 1 else { throw ExactRealTopologyFailure.invalidCoverage }
        }
        try ExactTopologyAccess.storage(n, ExactRealClosure<Base>.self, &a)
        var closures: [ExactRealClosure<Base>] = []; closures.reserveCapacity(n)
        for i in 0..<n {
            try ExactTopologyAccess.storage(closed[i].count, ExactRealCellInstruction.self, &a)
            let program = Array(f.instructions[closed[i]])
            let r = ExactRealTopologyRegion(partition: common.partition, coordinateCount: source.variableCount,
                cells: common.cells, included: closureMasks[i], excludesExterior: true, formulaAtoms: common.formulaAtoms,
                signInvariants: [], certifiedTarget: nil, reductions: [], eliminations: [], depth: counts.depth,
                decisions: [], quantifiers: [], instructions: program)
            closures.append(.init(definition: definitions[i], factors: factors[i], proof: .affine,
                region: r, applicability: nil, depth: counts.depth))
        }
        let pairCount = try ExactTopologyAccess.multiply(n, n)
        try ExactTopologyAccess.storage(pairCount, ExactRealIncidencePair<Base>.self, &a)
        var pairs: [ExactRealIncidencePair<Base>] = [], attachments: [ExactRealAttachment<Base>] = []
        pairs.reserveCapacity(pairCount)
        for i in 0..<n { for j in 0..<n {
            try a.consumeWork(1)
            let start = attachments.count
            var result: ExactRealTopologyRegion<Base>? = nil
            if i != j {
                try ExactTopologyAccess.storage(common.cells.count, Bool.self, &a)
                var included: [Bool] = []; included.reserveCapacity(common.cells.count)
                for k in common.cells.indices {
                    try a.consumeWork(1); included.append(closureMasks[i][k] && targetMasks[j][k])
                }
                let programCount = try ExactTopologyAccess.add(try ExactTopologyAccess.add(closed[i].count, strict[j].count), 1)
                try ExactTopologyAccess.storage(programCount, ExactRealCellInstruction.self, &a)
                var program: [ExactRealCellInstruction] = []; program.reserveCapacity(programCount)
                program.append(contentsOf: f.instructions[closed[i]]); program.append(contentsOf: f.instructions[strict[j]])
                program.append(.and)
                let region = ExactRealTopologyRegion(partition: common.partition, coordinateCount: source.variableCount,
                    cells: common.cells, included: included, excludesExterior: true, formulaAtoms: common.formulaAtoms,
                    signInvariants: [], certifiedTarget: selection.cells[j], reductions: [], eliminations: [], depth: counts.depth,
                    decisions: [], quantifiers: [], instructions: program)
                for k in common.cells.indices where included[k] {
                    try appendAttachment(source: selection.cells[i], target: selection.cells[j], closure: closures[i],
                        region: region, piece: common.cells[k], limits: limits, counts: &counts, attachments: &attachments, &a)
                }
                result = region
            }
            pairs.append(.init(source: selection.cells[i], target: selection.cells[j], region: result, attachments: start..<attachments.count))
        } }
        return .init(selection: copy selection, closures: closures, pairs: pairs, attachments: attachments, depth: counts.depth)
    }
}
