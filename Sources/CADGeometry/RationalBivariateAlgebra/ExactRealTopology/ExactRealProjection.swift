#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

/// Projected topology is distinct from topology in the lifted coordinate space.
public struct ExactRealProjection<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let original: ExactRealCellSelection<Base>
    public let selection: ExactRealCellSelection<Base>
    public let components: ExactRealComponents<Base>
    public var coordinateCount: Int { selection.partition.source.variableCount }
    public let depth: ExactScalarDepth
    let ordinals: [Int]
    let ranges: [Range<Int>]
    init(original: ExactRealCellSelection<Base>, selection: ExactRealCellSelection<Base>,
        components: ExactRealComponents<Base>, ordinals: [Int], ranges: [Range<Int>], depth: ExactScalarDepth) {
        self.original = original; self.selection = selection; self.components = components
        self.ordinals = ordinals; self.ranges = ranges; self.depth = depth
    }
    /// The returned view retains both original selection and immutable index storage.
    public func liftedCells(forProjectedOrdinal ordinal: Int) -> ExactRealProjectionLifts<Base>? {
        guard ordinal >= 0, ordinal < ranges.count else { return nil }
        return .init(original: original, indices: ordinals[ranges[ordinal]])
    }
}
