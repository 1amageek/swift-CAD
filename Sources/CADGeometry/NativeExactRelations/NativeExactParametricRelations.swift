#if NATIVE_FAMILY_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import SourceIssuer
import DI
#endif

/// Complete finite TUV/UVUV collection; every original chart side and lift survives.
public struct NativeExactParametricRelations<First: OriginalBSplineSourceReading,
    Second: OriginalBSplineSourceReading>: Sendable {
    public typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    public let first: OriginalBSplineDomainCover<First,Field>
    public let second: OriginalBSplineDomainCover<Second,Field>
    public let pieces: [NativeExactParametricRelationPiece<First,Second>]
    init(first: OriginalBSplineDomainCover<First,Field>,second: OriginalBSplineDomainCover<Second,Field>,
        pieces: [NativeExactParametricRelationPiece<First,Second>]) {
        self.first = first; self.second = second; self.pieces = pieces
    }
}
