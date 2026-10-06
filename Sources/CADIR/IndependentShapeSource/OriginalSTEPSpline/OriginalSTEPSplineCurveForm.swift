public enum OriginalSTEPSplineCurveForm: String, Sendable {
    case polyline = "POLYLINE_FORM", circularArc = "CIRCULAR_ARC", ellipticArc = "ELLIPTIC_ARC"
    case parabolicArc = "PARABOLIC_ARC", hyperbolicArc = "HYPERBOLIC_ARC", unspecified = "UNSPECIFIED"
    public var stepToken: String { "." + rawValue + "." }
}
#if !hasFeature(Embedded)
extension OriginalSTEPSplineCurveForm: Codable {}
#endif
