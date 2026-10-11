/// Immutable complete polynomial lift/plane family, separate from L5 cell-backed results.
public protocol OriginalContainedLiftPlaneFamilyReading: Sendable {
    var pieces: [OriginalContainedLiftPlanePiece] { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}
