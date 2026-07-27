import CADCore

/// A compact identity header for one certified surface-intersection component.
///
/// Derived curve and parameter-curve representations are intentionally excluded.
/// They can contain large copies of the same certificate and are not the source
/// identity used when topology groups trimmed intervals.
public struct SurfaceSurfaceIntersectionSourceIdentity: Hashable, Sendable {
    public let kind: CurveSurfaceIntersectionKind
    public let firstSurfaceAnchor: SurfaceParameterProjection
    public let secondSurfaceAnchor: SurfaceParameterProjection
    public let certificationTolerance: ModelingTolerance

    public init(
        kind: CurveSurfaceIntersectionKind,
        firstSurfaceAnchor: SurfaceParameterProjection,
        secondSurfaceAnchor: SurfaceParameterProjection,
        certificationTolerance: ModelingTolerance
    ) {
        self.kind = kind
        self.firstSurfaceAnchor = firstSurfaceAnchor
        self.secondSurfaceAnchor = secondSurfaceAnchor
        self.certificationTolerance = certificationTolerance
    }
}
