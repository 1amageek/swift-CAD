import CADCore

public struct AssemblyOccurrencePath: Codable, Hashable, Sendable, Comparable {
    public let components: [AssemblyOccurrenceID]
    public init(_ components: [AssemblyOccurrenceID]) { self.components = components }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
    public var description: String { components.map(\.description).joined(separator: "/") }
    private enum CodingKeys: String, CodingKey { case components }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.components], in: decoder)
        components = try c.decode([AssemblyOccurrenceID].self, forKey: .components)
        guard !components.isEmpty else { throw AssemblyError.invalidSource("Occurrence path is empty.") }
    }
}
