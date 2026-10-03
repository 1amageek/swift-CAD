public struct GeometryConversionGuarantee: Sendable {
    public let positionErrorUpperBound: Double
    public let tangentAngleUpperBound: Double
    public let curvatureErrorUpperBound: Double
    public let certifiedBoxCount: Int
}
