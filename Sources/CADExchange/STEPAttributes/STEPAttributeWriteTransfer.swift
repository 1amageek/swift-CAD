import CADIR

public struct STEPAttributeWriteTransfer: Sendable {
    public var products: [AssemblyDefinitionID: STEPAttributeProductRepresentation] = [:]
    public var usages: [AssemblyOccurrenceID: Int] = [:]
    public var relationships: [AssemblyOccurrenceID: Int] = [:]
    /// Retains the actual CDSR emitted for a direct source usage.
    public var usageContexts: [AssemblyOccurrenceID: Int] = [:]
    public init() {}
}
