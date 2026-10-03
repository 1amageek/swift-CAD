import CADCore
import CADIR

public struct STEPAttributeReadTransfer: Sendable {
    public var geometry: [Int: SubshapeID] = [:]
    public var geometryUnits: [Int: LengthUnit] = [:]
    public var definitions: [Int: AssemblyDefinitionID] = [:]
    public var representations: [Int: Set<AssemblyDefinitionID>] = [:]
    public var representationUnits: [Int: LengthUnit] = [:]
    public var partCarriers: [Int: AssemblyDefinitionID] = [:]
    public var usages: [Int: AssemblyOccurrenceID] = [:]
    public var relationships: [Int: AssemblyOccurrenceID] = [:]
    /// Maps a producer-validated CDSR entity to its real NAUO source identity.
    public var usageContexts: [Int: AssemblyOccurrenceID] = [:]
    public init() {}
}
