#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

/// Complete quantified classification; auxiliary witnesses are not free coordinates.
public struct ExactRealCellPullback<Base: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable where Base.Source == Base.Value {
    public let source: ExactRealCellSelection<Base>
    public let target: ExactRealCellPredicate<Base>
    public let coordinateMap: [Int]
    public let region: ExactRealTopologyRegion<Base>
    /// Aligned with region.cells. Excluded cells use -1; included cells have one source ordinal.
    public let sourceCellOrdinals: [Int]
    let labelInstructionRanges: [Range<Int>]
    init(source: ExactRealCellSelection<Base>, target: ExactRealCellPredicate<Base>,
         coordinateMap: [Int], region: ExactRealTopologyRegion<Base>,
         sourceCellOrdinals: [Int], labelInstructionRanges: [Range<Int>]) {
        self.source = source; self.target = target; self.coordinateMap = coordinateMap
        self.region = region; self.sourceCellOrdinals = sourceCellOrdinals
        self.labelInstructionRanges = labelInstructionRanges
    }
}
