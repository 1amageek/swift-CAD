import CADCore

public struct STEPAttributeProductRepresentation: Sendable {
    public let definition: Int
    public let definitionShape: Int
    public let representation: Int
    public let context: Int
    public let geometryRepresentation: Int
    public let carrier: Int?
    public let bodies: [BodyID: [Int]]
    public let faces: [FaceID: Int]
    public init(definition: Int, definitionShape: Int, representation: Int, context: Int,
                geometryRepresentation: Int, carrier: Int?, bodies: [BodyID: [Int]], faces: [FaceID: Int]) {
        self.definition = definition; self.definitionShape = definitionShape
        self.representation = representation; self.context = context
        self.geometryRepresentation = geometryRepresentation; self.carrier = carrier; self.bodies = bodies; self.faces = faces
    }
}
