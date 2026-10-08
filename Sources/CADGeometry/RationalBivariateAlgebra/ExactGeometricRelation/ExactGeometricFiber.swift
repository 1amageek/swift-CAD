#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

public struct ExactGeometricFiber<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let parent: ExactGeometricRelation<Base>
    public let station: ExactGeometricStation<Base>
    public let components: ExactRealComponents<Base>
    public var selection: ExactRealCellSelection<Base> { components.incidence.selection }
    public var isEmpty: Bool { selection.cells.isEmpty }
    init(parent: ExactGeometricRelation<Base>, station: ExactGeometricStation<Base>, components: ExactRealComponents<Base>) {
        self.parent = parent; self.station = station; self.components = components
    }
}
