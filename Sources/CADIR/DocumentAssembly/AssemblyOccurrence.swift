import CADCore
import CADGeometry

public struct AssemblyOccurrence: Codable, Equatable, Sendable {
    public let id: AssemblyOccurrenceID
    public var name: String
    public var definitionID: AssemblyDefinitionID
    public var placement: RigidTransform3D
    public init(id: AssemblyOccurrenceID = AssemblyOccurrenceID(), name: String = "",
                definitionID: AssemblyDefinitionID, placement: RigidTransform3D = .translated(by: .zero)) {
        self.id = id; self.name = name; self.definitionID = definitionID; self.placement = placement
    }
    private enum PlacementKeys: String, CodingKey { case basisX, basisY, basisZ, translation }
    private enum VectorKeys: String, CodingKey { case x, y, z }
    private enum CodingKeys: String, CodingKey { case id, name, definitionID, placement }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .definitionID, .placement], in: decoder)
        id = try c.decode(AssemblyOccurrenceID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        definitionID = try c.decode(AssemblyDefinitionID.self, forKey: .definitionID)
        let frameDecoder = try c.superDecoder(forKey: .placement)
        let frame = try frameDecoder.container(keyedBy: PlacementKeys.self)
        try frame.validateOnlyExpectedKeys([.basisX, .basisY, .basisZ, .translation], in: frameDecoder)
        for key in [PlacementKeys.basisX, .basisY, .basisZ, .translation] {
            let vectorDecoder = try frame.superDecoder(forKey: key)
            let vector = try vectorDecoder.container(keyedBy: VectorKeys.self)
            try vector.validateOnlyExpectedKeys([.x, .y, .z], in: vectorDecoder)
        }
        placement = try RigidTransform3D(from: frameDecoder)
    }
}
