import CADCore
import CADGeometry

public struct BooleanFaceSurfaceIntersection: Codable, Hashable, Sendable {
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
