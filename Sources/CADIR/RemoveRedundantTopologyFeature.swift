import CADCore
import CADGeometry

/// Delete Redundant Topology on a solid or a sheet: faces on one surface merge across the edges
/// between them and edges on one curve across the vertices between them, the shape unchanged.
public struct RemoveRedundantTopologyFeature: Hashable, Sendable {
    public var target: PatternTargetReference

    public init(target: PatternTargetReference) {
        self.target = target
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try target.validate()
        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
    }
#endif
}

#if !hasFeature(Embedded)
extension RemoveRedundantTopologyFeature: Codable {}
#endif
