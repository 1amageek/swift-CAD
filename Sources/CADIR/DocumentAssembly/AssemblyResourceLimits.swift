/// Operation ceilings for structural expansion and aggregate exact topology copies.
public struct AssemblyResourceLimits: Sendable, Equatable {
    public var maximumRecords: Int
    public var maximumTextBytes: Int
    public var maximumOccurrences: Int
    public var maximumDepth: Int
    /// Independent exact field ancestry and root refinement ceiling.
    public var maximumAlgebraicDepth: Int
    public var maximumTopologyEntities: Int
    /// Cumulative ceiling shared by source expansion, local extraction, and world placement.
    public var maximumWork: Int
    public init(maximumRecords: Int = 1_000_000, maximumOccurrences: Int = 1_000_000,
                maximumDepth: Int = 256, maximumTopologyEntities: Int = 10_000_000,
                maximumWork: Int = 100_000_000, maximumTextBytes: Int = 64 * 1024 * 1024,
                maximumAlgebraicDepth: Int = 32) {
        self.maximumTextBytes = maximumTextBytes
        self.maximumRecords = maximumRecords; self.maximumOccurrences = maximumOccurrences
        self.maximumDepth = maximumDepth; self.maximumTopologyEntities = maximumTopologyEntities
        self.maximumWork = maximumWork; self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }
    public static let standard = AssemblyResourceLimits()
    public func validate() throws {
        guard maximumTextBytes >= 0, maximumRecords > 0, maximumOccurrences > 0, maximumDepth > 0,
              maximumTopologyEntities > 0, maximumWork > 0,
              (0...32).contains(maximumAlgebraicDepth) else {
            throw AssemblyError.invalidSource("Assembly resource record/work limits must be positive, text storage nonnegative, and exact algebra depth in 0...32.")
        }
    }
}

#if !hasFeature(Embedded)
extension AssemblyResourceLimits: Codable {
    private enum CodingKeys: String, CodingKey {
        case maximumRecords, maximumTextBytes, maximumOccurrences, maximumDepth
        case maximumTopologyEntities, maximumWork, maximumAlgebraicDepth
    }
    public init(from decoder: any Decoder) throws {
        let object = try decoder.container(keyedBy: CodingKeys.self)
        self.init(maximumRecords: try object.decode(Int.self, forKey: .maximumRecords),
            maximumOccurrences: try object.decode(Int.self, forKey: .maximumOccurrences),
            maximumDepth: try object.decode(Int.self, forKey: .maximumDepth),
            maximumTopologyEntities: try object.decode(Int.self, forKey: .maximumTopologyEntities),
            maximumWork: try object.decode(Int.self, forKey: .maximumWork),
            maximumTextBytes: try object.decode(Int.self, forKey: .maximumTextBytes),
            maximumAlgebraicDepth: object.contains(.maximumAlgebraicDepth)
                ? try object.decode(Int.self, forKey: .maximumAlgebraicDepth) : 32)
        try validate()
    }
}
#endif
