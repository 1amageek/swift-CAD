import CADCore

/// Source-retaining UV relation. Coordinates describe uniquely scoped inverse
/// functions, not guessed scalar inverses or unchecked source certificates.
public struct OriginalBoundedSphereConeSurfaceUV: Sendable {
    public typealias Value = OriginalBoundedSphereConeSurfaceSnapshot.Field.Value
    public enum Coordinate: Sendable {
        /// B/(2*pi)*2*atan(t)+offset, with t>0 and angle in(0,pi).
        case coneAngularLabel(halfAngle: Value, period: Value, offset: Value)
        /// B/(2*pi)*atan2(sineArgument,cosineArgument)+offset, principal(-pi,pi].
        @available(*,deprecated,message:"Use the complete sphereAngularInverse relation.")
        case sphereAzimuthLabel(sineArgument: Value, cosineArgument: Value, period: Value, offset: Value)
        /// B/(2*pi)*asin(sine), on the original closed canonical latitude range.
        case sphereLatitudeLabel(sine: Value, period: Value)
        /// Every original U at the exact sphere pole.
        @available(*,deprecated,message:"The complete sphereAngularInverse retains the exact collapsed condition.")
        case collapsedAngularFamily(period:Value)
        /// Nonzero arguments: principal atan2 plus the selected integer lift.
        /// Exactly zero arguments: every original U; no atan2(0,0) is evaluated.
        case sphereAngularInverse(sineArgument:Value,cosineArgument:Value,period:Value,offset:Value)
        case authoredScalar(Value)
    }
    public let member: OriginalBoundedSphereConeSurfaceMember
    public let isSphere: Bool
    public let u: Coordinate
    public let v: Coordinate
}
