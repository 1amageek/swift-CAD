#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension ExactRealRootDomain: ExactRealRootTransporting where F: ExactScalarImporting, F.Source == F.Value {
    public func transport<A: ExactScalarAdmission & ~Copyable>(_ root: borrowing ExactRealRoot<F>,
        using admission: inout A) throws(ExactRealRootFailure) -> ExactRealRootTransport<F> {
        let root = copy root
        return try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            // Admit the source issuer's entire attained depth before importing or reusing anything.
            let originalDomain = ExactRealRootDomain(context: root.source.context)
            try originalDomain.admitted(root, &a)
            if root.source.context === context {
                return .init(original: root, transferred: root, depth: a.depth)
            }
            let original = try polynomials.importing(root.source.original, using: &a)
            let source = try bind(original, variable: root.source.variable,
                refinementAxis: root.source.refinementAxis, using: &a)
            guard case .finite(let lower) = root.isolation.lower,
                case .finite(let upper) = root.isolation.upper else { throw ExactRealRootFailure.invalidEvidence }
            let importedLower = try context.field.importing(lower, using: &a)
            let importedUpper = try context.field.importing(upper, using: &a)
            let selected = try interval(.finite(importedLower), .finite(importedUpper),
                root.isolation.includesLower, root.isolation.includesUpper, &a)
            let issued = try isolate(source, in: selected, limits: .init(maximumRoots: 1), using: &a)
            guard issued.roots.count == 1, let transferred = issued.roots.first,
                transferred.ordinal == root.ordinal, transferred.multiplicity == root.multiplicity else {
                throw ExactRealRootFailure.invalidEvidence
            }
            let law = try context.univariate.importing(root.proof.polynomial, using: &a)
            let divisor = try sourceForLaw(law, variable: root.source.variable,
                axis: root.source.refinementAxis, &a)
            let refined = try refine(transferred, usingDefiningDivisor: divisor, using: &a)
            return .init(original: root, transferred: refined, depth: a.depth)
        }
    }
}
