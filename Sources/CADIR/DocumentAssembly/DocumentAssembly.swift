import CADCore

public struct DocumentAssembly: Codable, Equatable, Sendable {
    public var products: [AssemblyProduct]
    public var formations: [AssemblyProductFormation]
    public var definitions: [AssemblyDefinition]
    public var roots: [AssemblyOccurrence]
    public init(products: [AssemblyProduct], formations: [AssemblyProductFormation], definitions: [AssemblyDefinition], roots: [AssemblyOccurrence]) {
        self.products = products; self.formations = formations; self.definitions = definitions; self.roots = roots
    }
    /// Stable source ordering; sibling order carries no assembly identity.
    package var canonicalized: DocumentAssembly {
        DocumentAssembly(products: products.sorted { $0.id < $1.id }, formations: formations.sorted { $0.id < $1.id }, definitions: definitions.sorted { $0.id < $1.id }.map {
            var d = $0; d.features.sort(); d.children.sort { $0.id < $1.id }; return d
        }, roots: roots.sorted { $0.id < $1.id })
    }
    private enum CodingKeys: String, CodingKey { case products, formations, definitions, roots }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.products, .formations, .definitions, .roots], in: decoder)
        products = try c.decode([AssemblyProduct].self, forKey: .products)
        formations = try c.decode([AssemblyProductFormation].self, forKey: .formations)
        definitions = try c.decode([AssemblyDefinition].self, forKey: .definitions)
        roots = try c.decode([AssemblyOccurrence].self, forKey: .roots)
    }
}
