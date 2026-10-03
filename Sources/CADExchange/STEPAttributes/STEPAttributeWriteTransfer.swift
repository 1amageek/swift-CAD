import CADIR

public struct STEPAttributeWriteTransfer: Sendable {
    public var products: [AssemblyDefinitionID: STEPAttributeProductRepresentation] = [:]
    public var usages: [AssemblyOccurrenceID: Int] = [:]
    public var relationships: [AssemblyOccurrenceID: Int] = [:]
    public init() {}
}
