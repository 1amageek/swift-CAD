#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// A checked coordinate correspondence; source laws are retained separately.
public struct OriginalDomainChart<S: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let transport: OriginalParameterTransport<S,F>
    public let selectedImage: OriginalParameterSelection<S,F>
    init(transport: OriginalParameterTransport<S,F>, selectedImage: OriginalParameterSelection<S,F>) {
        self.transport = transport; self.selectedImage = selectedImage
    }
}
