#if L5_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
#endif

/// All lifted witnesses remain owned; public parameter topology is that of the projection.
public struct ExactParametricGraphRelation<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let depth: ExactScalarDepth
    public let original: ExactParametricGraphRelationSource<Base>
    public let projection: ExactRealProjection<Base>
    public var selection: ExactRealCellSelection<Base> { projection.selection }
    public var components: ExactRealComponents<Base> { projection.components }
    init(original: ExactParametricGraphRelationSource<Base>, projection: ExactRealProjection<Base>, depth: ExactScalarDepth) {
        self.depth = depth; self.original = original; self.projection = projection
    }
    /// Reusing this L5 theorem admits all retained graph and simplification owners.
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(using admission: inout A) throws(ExactParametricRelationFailure) {
        do {
            try admission.checkpoint()
            try admission.admitDepth(value:depth.value,coefficient:depth.coefficient)
            try admission.checkpoint()
        } catch { throw .init(error) }
    }
}
