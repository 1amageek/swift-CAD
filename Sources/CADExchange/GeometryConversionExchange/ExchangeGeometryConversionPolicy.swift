import CADGeometry

public enum ExchangeGeometryConversionPolicy: Sendable {
    case exact
    case certified(GeometryConversionRequirements)
}
