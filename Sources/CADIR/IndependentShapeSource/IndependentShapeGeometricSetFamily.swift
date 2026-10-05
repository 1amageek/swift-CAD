/// A standard geometric selection family's original membership restriction.
public enum IndependentShapeGeometricSetFamily: String, Sendable {
    case geometric = "GEOMETRIC_SET"
    case curves = "GEOMETRIC_CURVE_SET"
}

#if !hasFeature(Embedded)
extension IndependentShapeGeometricSetFamily: Codable {}
#endif
