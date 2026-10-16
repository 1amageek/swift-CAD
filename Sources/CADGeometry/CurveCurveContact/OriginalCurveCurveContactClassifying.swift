import CADCore

public protocol OriginalCurveCurveContactClassifying: Sendable {
  func contacts(
    first: OriginalCurveContactSource, second: OriginalCurveContactSource,
    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
  ) throws -> OriginalCurveCurveContactClassification
}
