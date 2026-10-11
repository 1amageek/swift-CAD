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

/// One complete fundamental relation, repeated only by retained authored periods.
public struct NativeExactSymbolicRelationTemplate<First: OriginalBSplineSourceReading,
    Second: OriginalBSplineSourceReading>: Sendable {
    public let firstTemplate: Int
    public let secondTemplate: Int
    public let fundamental: NativeExactParametricRelationPiece<First,Second>

    init(firstTemplate: Int, secondTemplate: Int, fundamental: NativeExactParametricRelationPiece<First,Second>) {
        self.firstTemplate = firstTemplate
        self.secondTemplate = secondTemplate
        self.fundamental = fundamental
    }
}
