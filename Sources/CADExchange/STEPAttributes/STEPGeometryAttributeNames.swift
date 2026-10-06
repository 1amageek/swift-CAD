import CADCore

public struct STEPGeometryAttributeNames: Sendable {
    public let bodies: [BodyID: String]
    public let faces: [FaceID: String]
    public init(bodies: [BodyID: String], faces: [FaceID: String]) { self.bodies = bodies; self.faces = faces }
}
