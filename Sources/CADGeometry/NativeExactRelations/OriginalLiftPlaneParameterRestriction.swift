#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

/// Complete necessary plane-incidence preimage, retaining the original request and equation.
public struct OriginalLiftPlaneParameterRestriction<S: OriginalLiftGraphSourceReading,P: OriginalPlaneSourceReading>: Sendable {
    public typealias Member = OriginalDomainBoundParametricGraph<S,OriginalExactScalarDomain,OriginalSurfaceLiftGraphEvidence<S>>
    public enum Kind: Sendable { case unchanged, excluded, singleton(OriginalExactScalar) }
    public let original: Member
    public let selected: Member
    public let plane: OriginalSourceBinding<P>
    public let equation: ExactPolynomial<OriginalExactScalarDomain>
    public let kind: Kind
    public let depth: ExactScalarDepth
    init(original: Member,selected: Member,plane: OriginalSourceBinding<P>,equation: ExactPolynomial<OriginalExactScalarDomain>,kind: Kind,depth: ExactScalarDepth) {
        self.original = original; self.selected = selected; self.plane = plane; self.equation = equation; self.kind = kind; self.depth = depth
    }
}
