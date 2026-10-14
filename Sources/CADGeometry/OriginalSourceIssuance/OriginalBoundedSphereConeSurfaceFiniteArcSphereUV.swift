/// Exact original sphere inverse-coordinate arguments and intrinsic label scale.
public struct OriginalBoundedSphereConeSurfaceFiniteArcSphereUV: Sendable {
    public typealias Field = OriginalBoundedSphereConeSurfaceSnapshot.Field
    /// U=B*atan2(-(X-centerX),Y-centerY)/(2*pi), on (-B/2,0).
    public let x: OriginalBoundedSphereConeSurfaceFiniteArcCoordinate
    public let y: OriginalBoundedSphereConeSurfaceFiniteArcCoordinate
    /// V=B*asin((Z-centerZ)/radius)/(2*pi), on [-B/4,0].
    public let z: OriginalBoundedSphereConeSurfaceFiniteArcCoordinate
    public let centerX: Field.Value
    public let centerY: Field.Value
    public let centerZ: Field.Value
    public let radius: Field.Value
    public let labelPeriod: Field.Value
}
