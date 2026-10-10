#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

/// One isolated original parameter tuple with a valid retained auxiliary witness and exact XYZ.
public struct ExactGeometricGraphPoint<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let parent: ExactGeometricGraphRelation<Base>
    public let parameterOrdinal: Int
    public let witness: ExactRealCellSample<Base>
    public let parameters: [ExactAlgebraicScalarDomain<Base>.Value]
    public let position: ExactXYZ<Base>
    init(parent: ExactGeometricGraphRelation<Base>, parameterOrdinal: Int, witness: ExactRealCellSample<Base>,
        parameters: [ExactAlgebraicScalarDomain<Base>.Value], position: ExactXYZ<Base>) {
        self.parent = parent; self.parameterOrdinal = parameterOrdinal; self.witness = witness
        self.parameters = parameters; self.position = position
    }
}
