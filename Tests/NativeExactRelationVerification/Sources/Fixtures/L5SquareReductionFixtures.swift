import CADGeometry

/// Exercises the exact compiler boundary, including rejected reduction hypotheses.
public enum L5SquareReductionFixtures {
    public static func verify() throws {
        typealias Base = ExactRationalScalarDomain
        typealias Cells = ExactRealCellDomain<Base>
        for mode in 0..<6 {
            var a = try NativeExactFixtures.ledger()
            let field = try ExactAlgebraicScalarDomain.base(field: Base(), maximumExtensionLevel: 10, using: &a)
            let cells = try Cells(field: field, variableCount: 2, using: &a)
            let p = cells.polynomials
            let u = try p.variable(0, using: &a), v = try p.variable(1, using: &a)
            let zero = try p.zero(using: &a)
            let one = try p.constant(field.integer(1, using: &a), using: &a)
            let u2 = try p.multiplying(u, u, using: &a), v2 = try p.multiplying(v, v, using: &a)
            var law = try p.adding(u2, v2, using: &a)
            switch mode {
            case 1: law = try p.subtracting(zero, law, using: &a)
            case 2: law = try p.adding(law, one, using: &a)
            case 3: law = try p.subtracting(u2, v2, using: &a)
            case 4: law = try p.adding(law, p.multiplying(u, v, using: &a), using: &a)
            case 5: law = try p.adding(u, v2, using: &a)
            default: break
            }
            let roots = try ExactRealRootDomain(field: field, using: &a)
            let interval = try roots.domain(lower: .finite(field.integer(-1, using: &a)),
                upper: .finite(field.integer(1, using: &a)), using: &a)
            let left = try cells.bind(polynomials: [u, v, zero, one], domains: [interval, interval], using: &a)
            let right = try cells.bind(polynomials: [u, v, law, one], domains: [interval, interval], using: &a)
            let compiler = NativeExactFixtures.RelationDomain(cells: Cells.self, topology: .init(cells: Cells.self))
            let first = try compiler.map(from: left, using: &a), second = try compiler.map(from: right, using: &a)
            let source = try compiler.compile(kind: .surfaceSurface, first: first, second: second, using: &a)
            if mode < 2 {
                guard let proof = source.squareReduction else { throw NativeExactFixtures.Failure.invalidEvidence }
                try NativeExactFixtures.require(proof.factors.count == 2 && proof.positiveWeights.count == 2)
                try NativeExactFixtures.require(proof.negated == (mode == 0))
                for weight in proof.positiveWeights {
                    try NativeExactFixtures.require(try field.sign(of: weight, using: &a) == .positive)
                }
                // Check the published identity with a fresh retained polynomial domain.
                let retained = try ExactPolynomialDomain(retaining: proof.equation, using: &a)
                let signed = try retained.multiplying(proof.equation,
                    retained.constant(field.integer(proof.negated ? -1 : 1, using: &a), using: &a), using: &a)
                try NativeExactFixtures.require(try retained.equals(signed, proof.reconstructedIdentity, using: &a))
                try NativeExactFixtures.require(proof.divisions.count == 10)
                try NativeExactFixtures.require(source.rawEquations.count == 3 && source.predicate.source.polynomials.count == 7)
            } else {
                try NativeExactFixtures.require(source.squareReduction == nil)
                try NativeExactFixtures.require(source.predicate.source.polynomials.count == 5)
            }
        }
        print("PASS L5 exact square identities, retained reductions and rejected hypotheses")
    }
}
