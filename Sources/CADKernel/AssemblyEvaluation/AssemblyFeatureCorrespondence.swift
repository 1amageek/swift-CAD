import CADCore

public struct AssemblyFeatureCorrespondence: Codable, Sendable, Equatable {
    public let featureID: FeatureID
    public let bodies: [BodyID: BodyID]
    public let faces: [FaceID: FaceID]
    public let edges: [EdgeID: EdgeID]
    public let vertices: [VertexID: VertexID]
    public init(featureID: FeatureID, bodies: [BodyID: BodyID], faces: [FaceID: FaceID],
                edges: [EdgeID: EdgeID], vertices: [VertexID: VertexID]) {
        self.featureID = featureID; self.bodies = bodies; self.faces = faces
        self.edges = edges; self.vertices = vertices
    }
}
