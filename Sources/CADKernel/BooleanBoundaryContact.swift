import CADCore

public struct BooleanBoundaryContact: Codable, Hashable, Sendable {
    public let edgeID: EdgeID
    public let curveFaceID: FaceID
    public let surfaceFaceID: FaceID
    public let geometry: BooleanBoundaryContactGeometry

    public init(
        edgeID: EdgeID,
        curveFaceID: FaceID,
        surfaceFaceID: FaceID,
        geometry: BooleanBoundaryContactGeometry
    ) {
        self.edgeID = edgeID
        self.curveFaceID = curveFaceID
        self.surfaceFaceID = surfaceFaceID
        self.geometry = geometry
    }
}
