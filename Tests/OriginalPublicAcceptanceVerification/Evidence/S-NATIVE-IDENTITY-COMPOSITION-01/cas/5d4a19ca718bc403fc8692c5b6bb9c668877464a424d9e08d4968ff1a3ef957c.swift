/// A complete report for stored references and combinatorial incidence.
/// A clean report does not certify geometry or a valid modeling input.
public struct NonManifoldTopologyReport: Sendable, Equatable {
    public let issues: [TopologyRetentionIssue]
    public var hasStructuralDefects: Bool { !issues.isEmpty }
}
