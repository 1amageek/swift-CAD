/// Original cone Cartesian law at the retained exact ordered slant.
public struct OriginalBoundedSphereConeSurfaceFiniteArcCoordinate: Sendable {
    public typealias Field = OriginalBoundedSphereConeSurfaceSnapshot.Field
    /// X=A.x-s*lambda*sin(theta), Y=A.y+s*lambda*cos(theta), Z=A.z+c*lambda.
    public let axis: Int
    public let apex: Field.Value
    public let sourceSine: Field.Value
    public let sourceCosine: Field.Value
    public let slant: OriginalBoundedSphereConeSurfaceFiniteArcSlant
}
