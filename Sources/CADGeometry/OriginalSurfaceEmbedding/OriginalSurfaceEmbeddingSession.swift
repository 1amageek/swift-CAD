import CADCore

/// Immutable preparation shared by full-domain and material-trim consumers.
package protocol OriginalSurfaceEmbeddingSession: Sendable {
    var budget: OriginalQueryBudget { get }
    var executionLimits: OriginalQueryExecutionLimits { get }
    func certify(using execution: inout OriginalQueryExecution) throws
    func visitCrossContacts(
        using execution: inout OriginalQueryExecution,
        excluding: (SurfaceParameterBox, Int, inout OriginalQueryExecution) throws -> Bool,
        admit: (SurfaceSurfaceIntersection, SurfaceParameterBox, SurfaceParameterBox, Int, inout OriginalQueryExecution) throws -> Void
    ) throws
}

package extension OriginalSurfaceEmbeddingSession {
    func certify() throws {
        var execution = OriginalQueryExecution(budget: budget, limits: executionLimits)
        try certify(using: &execution)
    }
}
