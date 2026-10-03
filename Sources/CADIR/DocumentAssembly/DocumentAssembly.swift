import CADCore

public struct DocumentAssembly: Codable, Equatable, Sendable {
    public var definitions: [AssemblyDefinition]
    public var roots: [AssemblyOccurrence]
    public init(definitions: [AssemblyDefinition], roots: [AssemblyOccurrence]) {
        self.definitions = definitions; self.roots = roots
    }
    /// Stable source ordering; sibling order carries no assembly identity.
    package var canonicalized: DocumentAssembly {
        DocumentAssembly(definitions: definitions.sorted { $0.id < $1.id }.map {
            var d = $0; d.features.sort(); d.children.sort { $0.id < $1.id }; return d
        }, roots: roots.sorted { $0.id < $1.id })
    }
    private enum CodingKeys: String, CodingKey { case definitions, roots }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.definitions, .roots], in: decoder)
        definitions = try c.decode([AssemblyDefinition].self, forKey: .definitions)
        roots = try c.decode([AssemblyOccurrence].self, forKey: .roots)
    }
}
