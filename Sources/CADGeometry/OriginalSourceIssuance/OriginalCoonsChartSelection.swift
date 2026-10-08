#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Shares four complete source laws and eight immutable corner witnesses.
public struct OriginalCoonsChartSelection<Bottom: Sendable, BottomSelection: Sendable,
    Top: Sendable, TopSelection: Sendable, Left: Sendable, LeftSelection: Sendable,
    Right: Sendable, RightSelection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable {
    public let bottom: OriginalCoonsBoundarySelection<Bottom, BottomSelection, Field>
    public let top: OriginalCoonsBoundarySelection<Top, TopSelection, Field>
    public let left: OriginalCoonsBoundarySelection<Left, LeftSelection, Field>
    public let right: OriginalCoonsBoundarySelection<Right, RightSelection, Field>
    public init(bottom: OriginalCoonsBoundarySelection<Bottom, BottomSelection, Field>,
        top: OriginalCoonsBoundarySelection<Top, TopSelection, Field>,
        left: OriginalCoonsBoundarySelection<Left, LeftSelection, Field>,
        right: OriginalCoonsBoundarySelection<Right, RightSelection, Field>) {
        self.bottom = bottom; self.top = top; self.left = left; self.right = right
    }
}
