#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

extension ExactRealTopologyDomain {
    /// Reuses complete original signs for a unique continuous polynomial graph.
    func retainedPolynomialGraph<A: ExactScalarAdmission & ~Copyable>(
        _ definition: ExactRealCellDefinition<Base>, factors: [ExactRealTopologyFactor<Base>],
        counts: inout ExactTopologyCounts, cover: [ExactRealCellID<Base>]?, _ a: inout A
    ) throws -> ExactRealTopologyRegion<Base>? {
        guard try closedBox(definition.partition.source, &a) else { return nil }
        let n = definition.coordinateCount
        var base = 0
        for step in definition.steps {
            try a.consumeWork(1)
            if step.section == nil { base = step.axis + 1 }
        }
        guard base < n else { return nil }
        let helper = try formula(field: definition.coefficientField, free: n, quantifiers: [], &a)
        for axis in 0..<base {
            let step = definition.steps[axis]
            for position in 0..<3 {
                try a.consumeWork(1)
                guard let root = position == 0 ? step.section : position == 1 ? step.lower : step.upper else { continue }
                if try helper.factor(root, in: factors, &a) != nil || helper.affineLeading(root, &a) != nil { continue }
                for term in root.polynomial.terms {
                    for slot in term.powers.indices {
                        try a.consumeWork(1)
                        if slot != axis && term.powers[slot] != 0 { return nil }
                    }
                }
            }
        }
        for axis in base..<n {
            try a.consumeWork(1)
            guard let section = definition.steps[axis].section,
                try helper.polynomialLeading(section, &a) != nil else { return nil }
        }
        // Each suffix is globally a unique polynomial of earlier coordinates.
        // The graph map and coordinate projection are inverse continuous maps;
        // closed source-domain constraints are preserved at every finite limit.
        var f = helper
        var witness = n
        try f.cell(definition, map: map(n, &a), witness: &witness, weak: true,
            factors: factors, sectorOrderByThom: true, strictSections: true, &a)
        guard witness == n else { throw ExactRealTopologyFailure.invalidFormula }
        guard f.quantifiers.isEmpty,
            let certificate = try invariantAtoms(definition, atoms: f.atoms,
                instructions: f.instructions, quantifiers: f.quantifiers, counts: &counts,
                sourceSigns: true, projectionSigns: true, &a) else { return nil }
        return try affineRegion(definition, formula: f, certificate: certificate,
            counts: &counts, retainedCover: cover, &a)
    }
}
