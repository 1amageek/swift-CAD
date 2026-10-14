import CADCore
import CADGeometry

public struct BooleanFaceSurfaceIntersection: Hashable, Sendable {
    public let facePair: BooleanFacePairCandidate
    public let geometry: SurfaceSurfaceIntersection

    public init(
        facePair: BooleanFacePairCandidate,
        geometry: SurfaceSurfaceIntersection
    ) {
        self.facePair = facePair
        self.geometry = geometry
    }
}

#if !hasFeature(Embedded)
extension BooleanFaceSurfaceIntersection: Codable {}
#endif
