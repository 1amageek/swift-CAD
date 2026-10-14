/// Source-owned original UV redundancy, retaining the same exact symbolic point.
public enum OriginalBoundedSphereConeSurfaceFiniteArcUV: Sendable {
    public typealias Field = OriginalBoundedSphereConeSurfaceSnapshot.Field
    case cone(u: Field.Value, v: OriginalBoundedSphereConeSurfaceFiniteArcSlant)
    case sphere(OriginalBoundedSphereConeSurfaceFiniteArcSphereUV)
}
