import CADCore
import CADIR

public struct ResolvedProductTarget: Hashable, Sendable {
    public let topology: TopologyReference?
    public let definitionID: AssemblyDefinitionID?
    public let path: AssemblyOccurrencePath?
    public init(topology: TopologyReference? = nil, definitionID: AssemblyDefinitionID? = nil, path: AssemblyOccurrencePath? = nil) {
        self.topology = topology; self.definitionID = definitionID; self.path = path
    }
}
