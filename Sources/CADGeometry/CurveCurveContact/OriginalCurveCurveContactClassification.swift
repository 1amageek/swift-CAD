public enum OriginalCurveCurveContactClassification: Sendable {
    case isolated([OriginalCurveCurveContact])
    /// Original identity or an original native correspondence is an ambiguity witness.
    case continuousAmbiguity(first: OriginalCurveContactSource, second: OriginalCurveContactSource)
}
