public enum TopologyRetentionError: Error, Sendable, Equatable {
    case invalidLimits
    case resourceLimitExceeded(Resource)
    case modelingAdmissionRejected(NonManifoldTopologyReport)

    public enum Resource: Sendable, Equatable {
        case topologyRecords
        case work
        case diagnostics
    }
}
