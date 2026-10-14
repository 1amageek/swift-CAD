import CADCore

/// Sealed source-law position; no sampled XYZ replaces its exact defining root.
public struct OriginalBoundedSphereConeSurfaceFiniteArcPosition: Sendable {
    public typealias Field = OriginalBoundedSphereConeSurfaceSnapshot.Field
    public let source: OriginalSourceBinding<OriginalBoundedSphereConeSurfaceSnapshot>
    public let coneU: Field.Value
    /// Exact raw coneU minus coneCycle times the independently issued cone period.
    public let principalConeU: Field.Value
    public let coneCycle: ExactRationalCoefficient
    public let sphereCycle: ExactRationalCoefficient
    public let branch: Int
    public let slant: OriginalBoundedSphereConeSurfaceFiniteArcSlant
    public let x: OriginalBoundedSphereConeSurfaceFiniteArcCoordinate
    public let y: OriginalBoundedSphereConeSurfaceFiniteArcCoordinate
    public let z: OriginalBoundedSphereConeSurfaceFiniteArcCoordinate
    public let sphereInverse: OriginalBoundedSphereConeSurfaceFiniteArcSphereUV
    public let proofDepth: ExactScalarDepth
    public var coneUV: OriginalBoundedSphereConeSurfaceFiniteArcUV { .cone(u: coneU, v: slant) }
    public var sphereUV: OriginalBoundedSphereConeSurfaceFiniteArcUV { .sphere(sphereInverse) }
    public var firstUV: OriginalBoundedSphereConeSurfaceFiniteArcUV { source.original.sphereIsFirst ? sphereUV : coneUV }
    public var secondUV: OriginalBoundedSphereConeSurfaceFiniteArcUV { source.original.sphereIsFirst ? coneUV : sphereUV }
}
