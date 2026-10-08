import L0
import L1
import L2
import L3

public enum ProjectionProofFixtures {
    public static func verify() throws {
        var a = try CellFixtures.ledger()
        let (field, domain, all) = try CellFixtures.setup(2, &a), p = domain.polynomials
        let x = try p.variable(0, using: &a), y = try p.variable(1, using: &a)
        let branch = try p.subtracting(y, x, using: &a)
        let square = try p.multiplying(branch, branch, using: &a)
        let duplicate = try p.scaled(square, by: field.integer(2, using: &a), using: &a)
        let crossing = try p.multiplying(branch, p.adding(y, x, using: &a), using: &a)
        let source = try domain.bind(polynomials: [square, duplicate, crossing], domains: [all, all], using: &a)
        let partition = try domain.decompose(source, limits: .init(maximumStoredCells: 100, maximumRootsPerStack: 10), using: &a)
        let evidence = try domain.projectionEvidence(forAxis: 1, in: partition, using: &a)
        var normalization = 0, reductum = 0, principal = 0
        for witness in evidence {
            switch witness {
            case .normalization(let original, let result, let multiplier):
                try CellFixtures.require(p.equals(original, p.scaled(result, by: multiplier, using: &a), using: &a))
                normalization += 1
            case .reductum(let original, let result, let axis, let degree):
                try CellFixtures.require(p.degree(of: original, in: axis, using: &a) == degree)
                for term in result.terms { try CellFixtures.require(term.powers[axis] < degree) }
                reductum += 1
            case .principal(let first, let second, let result, let axis, let index):
                try CellFixtures.require(p.equals(result, p.principalSubresultants(first, second, eliminating: axis, using: &a).values[index], using: &a))
                principal += 1
            default: break
            }
        }
        try CellFixtures.require(normalization > 0 && reductum > 0 && principal > 0)
        try CellFixtures.require(source.polynomials.count == 3)
        var repeated = 0, sectors = 0
        for cell in partition.cells {
            let definition = try domain.definition(of: cell, in: partition, using: &a)
            let step = definition.steps.last!
            let stack = try domain.stackEvidence(over: step.parent, in: partition, using: &a)
            try CellFixtures.require(stack.effectiveDegrees.count >= stack.originalMultiplicities.count)
            try CellFixtures.require(stack.parentConditionSigns.count == stack.projection.parentConditions.count)
            try CellFixtures.require(stack.separations.count == max(0, stack.completeRoots.roots.count - 1))
            if let boundary = step.section, boundary.incomingMultiplicity == 2 {
                try CellFixtures.require(boundary.incomingDerivativeSigns.firstIndex(where: { $0 != .zero }) == 2)
                try CellFixtures.require(boundary.parentEvidence.originalMultiplicities[boundary.incomingLawIndex][boundary.rootOrdinal] == 2)
                try CellFixtures.require(stack.completeRoots.roots[boundary.rootOrdinal].multiplicity == 1)
                repeated += 1
            }
            if step.lower != nil && step.upper != nil { sectors += 1 }
        }
        try CellFixtures.require(repeated > 0 && sectors > 0)
        print("PASS: public projection provenance, whole-parent bindings, original multiplicity and L2 sector separation evidence")
    }
}
