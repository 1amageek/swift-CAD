import CADCore
import CADGeometry
import CADTopology

/// Curves along edges of a body or sheet: each chosen edge's exact curve over its trim, published
/// as the feature's curve output so a curve consumer (a pipe's or a sweep's path, a curve section)
/// can follow an edge.
public struct EdgeCurveFeature: Hashable, Sendable {
    public var source: FeatureID
    public var bodyRole: FeaturePort
    public var edges: [StableSubshapeReference]

    public init(source: FeatureID, bodyRole: FeaturePort = .body, edges: [StableSubshapeReference]) {
        self.source = source
        self.bodyRole = bodyRole
        self.edges = edges
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        func uniqueEdgeCount() throws -> Int {
            for reference in edges {
                try reference.chargeStructuralComparison(using: &execution)
            }
            return try OriginalParameterQueryStorage.set(edges, using: &execution).count
        }
        guard bodyRole == .body || bodyRole == .sheet else {
            throw FeatureEvaluationError.invalidGraph("Edge curves come from a body or a sheet.")
        }
        guard edges.isEmpty == false, (try uniqueEdgeCount()) == edges.count else {
            throw FeatureEvaluationError.invalidGraph("Edge curves need one or more distinct edges.")
        }

        try execution.checkpoint()
    }
}

#if !hasFeature(Embedded)
extension EdgeCurveFeature: Codable {}
#endif
