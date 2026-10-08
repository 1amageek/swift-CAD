#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

public struct ExactGeometricStratumID<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable, Equatable where Base.Source == Base.Value {
    let owner: ExactGeometricRelationStorage<Base>
    public let ordinal: Int
    init(owner: ExactGeometricRelationStorage<Base>, ordinal: Int) { self.owner = owner; self.ordinal = ordinal }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.owner === rhs.owner && lhs.ordinal == rhs.ordinal }
}
