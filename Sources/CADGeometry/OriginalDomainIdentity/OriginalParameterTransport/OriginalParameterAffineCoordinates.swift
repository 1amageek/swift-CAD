#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Retains the checked map; coefficient readers share its immutable COW buffers.
public struct OriginalParameterAffineCoordinates<Source: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let transport: OriginalParameterTransport<Source,F>
    public var local: OriginalParameterSelection<Source,F> { transport.local }
    public var image: OriginalParameterSelection<Source,F> { transport.image }
    public var depth: Int { transport.depth }
    /// For each output axis i: image[i] = gains[i] * local[permutation[i]] + offsets[i].
    public var permutation: [Int] { transport.permutation }
    public var gains: [F.Value] { transport.gains }
    public var offsets: [F.Value] { transport.offsets }
    init(transport: OriginalParameterTransport<Source,F>) { self.transport = transport }
}
