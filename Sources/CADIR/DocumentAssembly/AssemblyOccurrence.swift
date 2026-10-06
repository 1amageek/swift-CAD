import CADCore
import CADGeometry

public struct AssemblyOccurrence: Equatable, Sendable {
    public let id: AssemblyOccurrenceID
    public var name: String
    public var definitionID: AssemblyDefinitionID
    public var placement: AssemblyPlacement
    public init(id: AssemblyOccurrenceID = AssemblyOccurrenceID(), name: String = "",
                definitionID: AssemblyDefinitionID, placement: RigidTransform3D = .translated(by: .zero)) {
        self.id = id; self.name = name; self.definitionID = definitionID; self.placement = .rigid(placement)
    }
    public init(id: AssemblyOccurrenceID = AssemblyOccurrenceID(), name: String = "",
                definitionID: AssemblyDefinitionID, sourcePlacement: AssemblyPlacement) {
        self.id = id; self.name = name; self.definitionID = definitionID; placement = sourcePlacement
    }
    public init(id: AssemblyOccurrenceID = AssemblyOccurrenceID(), name: String = "",
                definitionID: AssemblyDefinitionID, sourcePlacementWord: AssemblyPlacementWord) {
        self.init(id: id, name: name, definitionID: definitionID, sourcePlacement: .word(sourcePlacementWord))
    }
#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, definitionID, placement }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .definitionID, .placement], in: decoder)
        id = try c.decode(AssemblyOccurrenceID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        definitionID = try c.decode(AssemblyDefinitionID.self, forKey: .definitionID)
        placement = try c.decode(AssemblyPlacement.self, forKey: .placement)
    }
#endif
}
#if !hasFeature(Embedded)
extension AssemblyOccurrence: Codable {}
#endif
