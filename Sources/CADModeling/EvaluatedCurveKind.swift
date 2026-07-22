/// The semantic curve category exposed by modeling results and queries.
public enum EvaluatedCurveKind: Codable, Sendable, Hashable {
    case line
    case circle
    case arc
    case spline
}
