/// Explicit bounds for topology records, traversal work and diagnostic output.
public struct TopologyRetentionLimits: Sendable, Equatable {
    public let maximumTopologyRecords: Int
    public let maximumWork: Int
    public let maximumDiagnostics: Int

    public init(maximumTopologyRecords: Int, maximumWork: Int, maximumDiagnostics: Int) throws {
        guard maximumTopologyRecords > 0, maximumWork > 0, maximumDiagnostics > 0 else {
            throw TopologyRetentionError.invalidLimits
        }
        self.maximumTopologyRecords = maximumTopologyRecords
        self.maximumWork = maximumWork
        self.maximumDiagnostics = maximumDiagnostics
    }
}
