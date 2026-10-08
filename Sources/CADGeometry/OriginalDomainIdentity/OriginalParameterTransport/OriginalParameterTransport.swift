#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Checked bijection between supported selections. Periodicity of the source is a separate proof.
public struct OriginalParameterTransport<Source: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let local: OriginalParameterSelection<Source,F>
    public let image: OriginalParameterSelection<Source,F>
    public let depth: Int
    let permutation: [Int]
    let gains: [F.Value]
    let offsets: [F.Value]
    init(local: OriginalParameterSelection<Source,F>, image: OriginalParameterSelection<Source,F>,
        permutation: [Int], gains: [F.Value], offsets: [F.Value], depth: Int) {
        self.local = local; self.image = image; self.permutation = permutation
        self.gains = gains; self.offsets = offsets; self.depth = depth
    }
}
