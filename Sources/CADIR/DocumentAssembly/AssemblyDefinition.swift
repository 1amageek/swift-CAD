import CADCore

public struct AssemblyDefinition: Codable, Equatable, Sendable {
    public let id: AssemblyDefinitionID
    public var name: String
    public var features: [FeatureID]
    public var children: [AssemblyOccurrence]
    public init(id: AssemblyDefinitionID = AssemblyDefinitionID(), name: String = "",
                features: [FeatureID] = [], children: [AssemblyOccurrence] = []) {
        self.id = id; self.name = name; self.features = features; self.children = children
    }
    private enum CodingKeys: String, CodingKey { case id, name, features, children }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .features, .children], in: decoder)
        id = try c.decode(AssemblyDefinitionID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        features = try c.decode([FeatureID].self, forKey: .features)
        children = try c.decode([AssemblyOccurrence].self, forKey: .children)
    }
}
