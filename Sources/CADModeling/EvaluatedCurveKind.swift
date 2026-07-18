/// The semantic curve category exposed by modeling results and queries.
public enum EvaluatedCurveKind: Sendable, Hashable {
    case line
    case circle
    case arc
    case spline
}
