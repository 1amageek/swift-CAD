#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Nonforgeable scoped evidence. Equality of XYZ does not create this receipt.
public struct OriginalParameterIdentity<S: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    final class Proof: Sendable {
        let sources: [OriginalSourceBinding<S>]
        let laws: [ExactPolynomial<F>]
        let periods: [OriginalSourcePeriodReceipt<S,F>]
        let poles: [OriginalSourcePoleReceipt<S,F>]
        let boundaries: [OriginalSourceBoundaryDeclaration<S>]
        let parents: [OriginalParameterIdentity<S,F>]
        init(sources: [OriginalSourceBinding<S>],laws: [ExactPolynomial<F>],periods: [OriginalSourcePeriodReceipt<S,F>],boundaries: [OriginalSourceBoundaryDeclaration<S>],poles: [OriginalSourcePoleReceipt<S,F>],parents: [OriginalParameterIdentity<S,F>]) {
            self.sources = sources; self.laws = laws; self.periods = periods; self.boundaries = boundaries; self.poles = poles; self.parents = parents
        }
    }
    public let kind: OriginalParameterIdentityKind
    public let left: OriginalParameterSelection<S,F>
    public let right: OriginalParameterSelection<S,F>
    public let depth: Int
    public let proofCount: Int
    public let evidenceDepth: ExactScalarDepth
    public let evidenceSourceDepth: Int
    let permutation: [Int]?
    let gains: [F.Value]
    let offsets: [F.Value]
    let proof: Proof
    init(kind: OriginalParameterIdentityKind,left: OriginalParameterSelection<S,F>,right: OriginalParameterSelection<S,F>,
        permutation: [Int]?,gains: [F.Value],offsets: [F.Value],depth: Int,proofCount: Int,evidenceDepth: ExactScalarDepth,evidenceSourceDepth: Int,proof: Proof) {
        self.kind = kind; self.left = left; self.right = right; self.permutation = permutation
        self.gains = gains; self.offsets = offsets; self.depth = depth; self.proofCount = proofCount; self.evidenceDepth = evidenceDepth; self.evidenceSourceDepth = evidenceSourceDepth; self.proof = proof
    }
}
