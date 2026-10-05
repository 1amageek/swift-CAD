/// Original knot classification, independent of derived compressed knot storage.
public enum OriginalSTEPSplineKnotSpecification: String, Sendable {
    case uniform = "UNIFORM_KNOTS", quasiUniform = "QUASI_UNIFORM_KNOTS"
    case piecewiseBezier = "PIECEWISE_BEZIER_KNOTS", unspecified = "UNSPECIFIED"
    public var stepToken: String { "." + rawValue + "." }
}
#if !hasFeature(Embedded)
extension OriginalSTEPSplineKnotSpecification: Codable {}
#endif
