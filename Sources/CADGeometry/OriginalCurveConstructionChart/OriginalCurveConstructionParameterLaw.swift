/// The retained original parameter law of a construction chart.
public enum OriginalCurveConstructionParameterLaw: String, Hashable, Sendable {
    case affine
    case circularRational
    case hyperbolicRational
}

#if !hasFeature(Embedded)
extension OriginalCurveConstructionParameterLaw: Codable {}
#endif
