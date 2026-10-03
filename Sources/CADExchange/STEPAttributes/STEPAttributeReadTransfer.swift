import CADCore
import CADIR

public struct STEPAttributeReadTransfer: Sendable {
    public var geometry: [Int: SubshapeID] = [:]
    public var definitions: [Int: AssemblyDefinitionID] = [:]
    public var representations: [Int: AssemblyDefinitionID] = [:]
    public var partCarriers: [Int: AssemblyDefinitionID] = [:]
    public var usages: [Int: AssemblyOccurrenceID] = [:]
    public var relationships: [Int: AssemblyOccurrenceID] = [:]
    public init() {}
}
