import CADCore

public protocol OriginalCurveCurveContactClassifying: Sendable {
    func contacts(first: OriginalCurveContactSource, second: OriginalCurveContactSource,
                  allowance: inout OriginalCurveContactAllowance,
                  tolerance: ModelingTolerance) throws -> OriginalCurveCurveContactClassification
}
