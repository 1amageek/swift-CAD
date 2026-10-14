/// Source-retaining inverse U and exact signed V, without a fabricated mixed field.
public struct OriginalFullConeConeSurfaceUV: Sendable {
    public typealias Value = OriginalFullConeConeSurfaceSnapshot.Field.Value
    public enum AngularCoordinate: Sendable {
        /// B/(2*pi)*2*atan(t)+offset, t in[-1,1], offset includes chart*B/2.
        case circleChart(halfAngle: Value, period: Value, offset: Value)
        /// B/(2*pi)*atan2(sineArgument,cosineArgument)+offset; cosineArgument>0.
        /// Negative parameterized slant contributes B/2 to offset.
        case principalAzimuth(sineArgument: Value, cosineArgument: Value, period: Value, offset: Value)
    }
    public let member: OriginalFullConeConeSurfaceMember
    public let isReference: Bool
    public let u: AngularCoordinate
    public let v: OriginalConeConeSurfaceCoordinate
}
