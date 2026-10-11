/// Sealed complete family; empty template selections preserve their exclusion owners.
public struct OriginalContainedLiftPlaneFamily: OriginalContainedLiftPlaneFamilyReading {
    public let pieces: [OriginalContainedLiftPlanePiece]
    public let isEmpty: Bool
    public let hasPositiveDimensionalSolutions: Bool
    public let hasPositiveDimensionalImage: Bool
    init(pieces: [OriginalContainedLiftPlanePiece], isEmpty: Bool,
        hasPositiveDimensionalSolutions: Bool, hasPositiveDimensionalImage: Bool) {
        self.pieces = pieces; self.isEmpty = isEmpty
        self.hasPositiveDimensionalSolutions = hasPositiveDimensionalSolutions
        self.hasPositiveDimensionalImage = hasPositiveDimensionalImage
    }
}
