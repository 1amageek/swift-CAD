import CADCore

public struct ProductAttributes: Codable, Equatable, Sendable {
    public var materials: [PhysicalMaterialDescriptor]
    public var assignments: [ProductAttributeAssignment]
    public var layers: [ProductLayer]
    public init(materials: [PhysicalMaterialDescriptor] = [], assignments: [ProductAttributeAssignment] = [], layers: [ProductLayer] = []) {
        self.materials = materials; self.assignments = assignments; self.layers = layers
    }
    public var isEmpty: Bool { materials.isEmpty && assignments.isEmpty && layers.isEmpty }
    public var canonicalized: Self {
        Self(materials: materials.sorted { $0.id < $1.id }, assignments: assignments.sorted { $0.id < $1.id },
             layers: layers.sorted { $0.id < $1.id })
    }
    private enum CodingKeys: String, CodingKey { case materials, assignments, layers }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.materials, .assignments, .layers], in: decoder)
        materials = try c.decode([PhysicalMaterialDescriptor].self, forKey: .materials)
        assignments = try c.decode([ProductAttributeAssignment].self, forKey: .assignments)
        layers = try c.decode([ProductLayer].self, forKey: .layers)
    }
}
