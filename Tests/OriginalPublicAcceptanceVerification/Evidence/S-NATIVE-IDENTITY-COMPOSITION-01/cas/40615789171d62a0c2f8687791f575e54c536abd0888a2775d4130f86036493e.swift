#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

/// Indexed immutable proof of the complete fiber partition over one parent cell.
public struct ExactRealCellStackEvidence<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public typealias Field = ExactAlgebraicScalarDomain<Base>
    public let parent: ExactRealCellID<Base>
    let stackIndex: Int
    public var axis: Int { parent.owner.stacks[stackIndex].axis }
    public var completeRoots: ExactRealRootSet<Field> { parent.owner.stacks[stackIndex].rootSet }
    public var effectiveDegrees: [Int] { parent.owner.stacks[stackIndex].effectiveDegrees }
    public var parentConditionSigns: [ExactSign] { parent.owner.stacks[stackIndex].parentConditionSigns }
    public var originalMultiplicities: [[Int]] { parent.owner.stacks[stackIndex].rootMultiplicities }
    public var separations: [ExactRealRootSeparation<Field>] { parent.owner.stacks[stackIndex].separations }
    public var projection: ExactRealCellProjectionEvidence<Base> { .init(owner: parent.owner, axis: axis) }
}
