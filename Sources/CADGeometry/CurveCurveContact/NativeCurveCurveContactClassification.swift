/// Distinguishes complete isolated coverage from a proved continuous ambiguity.
public enum NativeCurveCurveContactClassification: Sendable {
    /// Every native parameter-pair cell was excluded or covered by an isolated receipt.
    case isolated([NativeCurveCurveContact])
    /// A positive-width original correspondence proves that unique contact selection fails.
    /// This witness does not assert absence of additional off-correspondence contacts.
    case continuousAmbiguity(NativeCurveCurveContact)
}
