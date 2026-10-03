/// Operation ceilings for structural expansion and aggregate exact topology copies.
public struct AssemblyResourceLimits: Codable, Sendable, Equatable {
    public var maximumRecords: Int
    public var maximumTextBytes: Int
    public var maximumOccurrences: Int
    public var maximumDepth: Int
    public var maximumTopologyEntities: Int
    /// Cumulative ceiling shared by source expansion, local extraction, and world placement.
    public var maximumWork: Int
    public init(maximumRecords: Int = 1_000_000, maximumOccurrences: Int = 1_000_000,
                maximumDepth: Int = 256, maximumTopologyEntities: Int = 10_000_000,
                maximumWork: Int = 100_000_000, maximumTextBytes: Int = 64 * 1024 * 1024) {
        self.maximumTextBytes = maximumTextBytes
        self.maximumRecords = maximumRecords; self.maximumOccurrences = maximumOccurrences
        self.maximumDepth = maximumDepth; self.maximumTopologyEntities = maximumTopologyEntities
        self.maximumWork = maximumWork
    }
    public static let standard = AssemblyResourceLimits()
    public func validate() throws {
        guard maximumTextBytes >= 0, maximumRecords > 0, maximumOccurrences > 0, maximumDepth > 0,
              maximumTopologyEntities > 0, maximumWork > 0 else {
            throw AssemblyError.invalidSource("Assembly resource record/work limits must be positive and text storage nonnegative.")
        }
    }
}
