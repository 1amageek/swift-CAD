#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

/// Station fibers are projected before topology; auxiliary degrees of freedom are not parameter fibers.
public struct ExactGeometricGraphFiber<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let parent: ExactGeometricGraphRelation<Base>
    public let station: ExactGeometricStation<Base>
    public let usesParameterProjection: Bool
    /// Original auxiliary correspondence. A lift belongs to this fiber only when
    /// its parameter tuple also satisfies `selection`; use `containsLift` to check both.
    public var sourceProjection: ExactRealProjection<Base> { parent.original.projection }
    public let projection: ExactRealProjection<Base>
    public var components: ExactRealComponents<Base> { projection.components }
    public var selection: ExactRealCellSelection<Base> { projection.selection }
    init(parent: ExactGeometricGraphRelation<Base>, station: ExactGeometricStation<Base>, projection: ExactRealProjection<Base>, usesParameterProjection: Bool) {
        self.parent = parent; self.station = station; self.projection = projection; self.usesParameterProjection = usesParameterProjection
    }
}
