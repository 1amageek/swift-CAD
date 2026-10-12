#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain: ExactRealProjectionProducing where Cells: ExactRealCellSelecting {
    public func project<A: ExactScalarAdmission & ~Copyable>(_ selection: borrowing ExactRealCellSelection<Base>,
        retainingPrefix k: Int, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using a: inout A)
        throws(ExactRealTopologyFailure) -> ExactRealProjection<Base> {
        do {
            try a.checkpoint()
            let n = selection.partition.source.variableCount
            guard k >= 0, k <= n else { throw ExactRealTopologyFailure.invalidDefinition }
            var counts = ExactTopologyCounts(depth: selection.depth)
            try counts.retain(selection.depth, &a)
            let cells = try Cells(retaining: selection.partition.source, using: &a)
            let field = try cells.coefficientField(of: selection.partition.source, using: &a)
            if k == n {
                // Identity projection shares the original CAD instead of solving it again.
                try ExactTopologyAccess.storage(selection.cells.count, Int.self, &a)
                try ExactTopologyAccess.storage(selection.cells.count, Range<Int>.self, &a)
                var ordinals: [Int] = [], ranges: [Range<Int>] = []
                ordinals.reserveCapacity(selection.cells.count); ranges.reserveCapacity(selection.cells.count)
                for i in 0..<selection.cells.count { try a.consumeWork(1); ordinals.append(i); ranges.append(i..<(i+1)) }
                let incidence = try self.incidence(of: selection, strategy: .automatic, limits: topologyLimits, using: &a)
                let components = try self.components(of: incidence, limits: topologyLimits, using: &a)
                try counts.retain(components.depth, &a)
                try ExactTopologyAccess.storage(1, ExactRealProjection<Base>.self, &a)
                let result = ExactRealProjection(original: copy selection, selection: copy selection, components: components,
                    ordinals: ordinals, ranges: ranges, depth: counts.depth)
                try a.checkpoint(); return result
            }
            try ExactTopologyAccess.storage(selection.cells.count, ExactRealCellID<Base>.self, &a)
            try ExactTopologyAccess.storage(selection.cells.count, Int.self, &a)
            var prefixes: [ExactRealCellID<Base>] = [], groups: [Int] = []
            prefixes.reserveCapacity(selection.cells.count); groups.reserveCapacity(selection.cells.count)
            // A CAD stack covers its entire parent cell, even for unbounded fibers.
            for leaf in selection.cells {
                try a.consumeWork(1)
                var parent = leaf
                while (parent.axis ?? -1) + 1 > k {
                    try a.consumeWork(1)
                    guard let next = parent.parent else { throw ExactRealTopologyFailure.invalidCoverage }
                    parent = next
                }
                guard (parent.axis ?? -1) + 1 == k else { throw ExactRealTopologyFailure.invalidCoverage }
                var found: Int? = nil
                for i in prefixes.indices { try a.consumeWork(1); if prefixes[i] == parent { found = i; break } }
                if let found { groups.append(found) }
                else { groups.append(prefixes.count); prefixes.append(parent) }
            }
            // Retain original arity while serializing prefix definitions. Afterwards,
            // prove all eliminated powers vanish before lowering the polynomial ring.
            var f = try formula(field: field, free: n, quantifiers: [], &a)
            let identity = try map(n, &a)
            try ExactTopologyAccess.storage(prefixes.count, Range<Int>.self, &a)
            var programs: [Range<Int>] = []; programs.reserveCapacity(prefixes.count)
            try f.instruction(.literal(false), &a)
            var witness = n
            for prefix in prefixes {
                let definition = try cells.definition(of: prefix, in: selection.partition, using: &a)
                try counts.retain(definition.depth, &a)
                let start = f.instructions.count
                try f.cell(definition, map: identity, witness: &witness, weak: false, sectorOrderByThom: true, &a)
                programs.append(start..<f.instructions.count)
                try f.instruction(.or, &a)
            }
            guard witness == n else { throw ExactRealTopologyFailure.invalidFormula }
            let projectedCells = try Cells(field: field, variableCount: k, using: &a)
            let ring = projectedCells.polynomials
            try ExactTopologyAccess.storage(f.atoms.count, Polynomial.self, &a)
            var laws: [Polynomial] = []; laws.reserveCapacity(f.atoms.count)
            for law in f.atoms {
                try counts.retain(law.depth, &a)
                try ExactTopologyAccess.storage(law.termCount, ExactPolynomialTerm<Field.Value>.self, &a)
                var terms: [ExactPolynomialTerm<Field.Value>] = []; terms.reserveCapacity(law.termCount)
                for term in law.terms {
                    try a.consumeWork(1)
                    for i in k..<n { try a.consumeWork(1); guard term.powers[i] == 0 else { throw ExactRealTopologyFailure.invalidFormula } }
                    try ExactTopologyAccess.storage(k, Int.self, &a)
                    var powers: [Int] = []; powers.reserveCapacity(k)
                    for i in 0..<k { try a.consumeWork(1); powers.append(term.powers[i]) }
                    terms.append(.init(powers: powers, coefficient: try field.importing(term.coefficient, using: &a)))
                }
                laws.append(try ring.polynomial(terms: terms, using: &a))
            }
            try ExactTopologyAccess.storage(k, ExactRealRootInterval<Field.Value>.self, &a)
            var domains: [ExactRealRootInterval<Field.Value>] = []; domains.reserveCapacity(k)
            for i in 0..<k { try a.consumeWork(1); domains.append(selection.partition.source.domains[i]) }
            let source = try projectedCells.bind(polynomials: laws, domains: domains, using: &a)
            let predicate = try projectedCells.predicate(instructions: f.instructions, for: source, using: &a)
            let bounded = try ExactRealCellLimits(maximumStoredCells: min(cellLimits.maximumStoredCells, topologyLimits.maximumGeneratedCells),
                maximumRootsPerStack: min(cellLimits.maximumRootsPerStack, topologyLimits.maximumRootsPerStack))
            let partition = try projectedCells.decompose(source, limits: bounded, using: &a)
            try counts.retain(partition.depth, &a)
            let selected = try projectedCells.select(partition, matching: predicate, using: &a)
            try counts.retain(selected.depth, &a)
            // Attribute every lift using whole-cell signs of the same projected CAD.
            try ExactTopologyAccess.storage(selected.cells.count, Range<Int>.self, &a)
            try ExactTopologyAccess.storage(programs.count, Bool.self, &a)
            try ExactTopologyAccess.storage(f.instructions.count, Bool.self, &a)
            var ranges: [Range<Int>] = []; ranges.reserveCapacity(selected.cells.count)
            var matched = [Bool](repeating: false, count: programs.count)
            var stack: [Bool] = []; stack.reserveCapacity(f.instructions.count)
            var ordinals: [Int] = []
            for cell in selected.cells {
                let start = ordinals.count
                for i in programs.indices {
                    stack.removeAll(keepingCapacity: true)
                    for offset in programs[i] {
                        try a.consumeWork(1)
                        switch f.instructions[offset] {
                        case .literal(let value): stack.append(value)
                        case .sign(let index, let relation):
                            guard index >= 0, index < cell.signs.count else { throw ExactRealTopologyFailure.invalidFormula }
                            stack.append(ExactTopologyAccess.accepts(cell.signs[index], relation))
                        case .not:
                            guard let value = stack.popLast() else { throw ExactRealTopologyFailure.invalidFormula }; stack.append(!value)
                        case .and, .or:
                            guard let right = stack.popLast(), let left = stack.popLast() else { throw ExactRealTopologyFailure.invalidFormula }
                            if case .and = f.instructions[offset] { stack.append(left && right) } else { stack.append(left || right) }
                        }
                    }
                    guard stack.count == 1 else { throw ExactRealTopologyFailure.invalidFormula }
                    matched[i] = stack[0]
                }
                for i in groups.indices {
                    try a.consumeWork(1)
                    if matched[groups[i]] {
                        // Growth is conservatively admitted before Array may allocate.
                        try ExactTopologyAccess.storage(ExactTopologyAccess.add(ordinals.count, 1), Int.self, &a)
                        ordinals.append(i)
                    }
                }
                guard start < ordinals.count else { throw ExactRealTopologyFailure.invalidCoverage }
                ranges.append(start..<ordinals.count)
            }
            // Projected CAD construction and closure refinements share the generated-cell cap.
            guard partition.storedCellCount <= topologyLimits.maximumGeneratedCells else { throw ExactRealTopologyFailure.generatedCellLimit }
            let remaining = try ExactRealTopologyLimits(maximumGeneratedCells: topologyLimits.maximumGeneratedCells-partition.storedCellCount,
                maximumRootsPerStack: topologyLimits.maximumRootsPerStack, maximumClosures: topologyLimits.maximumClosures,
                maximumAttachmentPieces: topologyLimits.maximumAttachmentPieces, maximumComponents: topologyLimits.maximumComponents)
            let incidence = try self.incidence(of: selected, strategy: .automatic, limits: remaining, using: &a)
            let components = try self.components(of: incidence, limits: remaining, using: &a)
            try counts.retain(components.depth, &a)
            try ExactTopologyAccess.storage(1, ExactRealProjection<Base>.self, &a)
            let result = ExactRealProjection(original: copy selection, selection: selected, components: components,
                ordinals: ordinals, ranges: ranges, depth: counts.depth)
            try a.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
}
