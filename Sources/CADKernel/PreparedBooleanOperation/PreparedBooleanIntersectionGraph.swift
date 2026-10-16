import CADCore
import CADGeometry
import CADIR
import CADTopology

/// An immutable producer-bound graph and its identical admitted original source.
public struct PreparedBooleanIntersectionGraph: Sendable {
    public let intersectionGraph: BooleanIntersectionGraph
    public let validatedModel: ValidatedBRepModel
    public let targetBodyIDs: [BodyID]
    public let toolBodyID: BodyID?
    package let classifications: PreparedSolidClassificationPair?

    fileprivate init(graph: BooleanIntersectionGraph, validatedModel: ValidatedBRepModel,
        targetBodyIDs: [BodyID], toolBodyID: BodyID?,
        classifications: PreparedSolidClassificationPair? = nil) {
        intersectionGraph = graph
        self.validatedModel = validatedModel
        self.targetBodyIDs = targetBodyIDs
        self.toolBodyID = toolBodyID
        self.classifications = classifications
    }
}

extension BooleanPipeline {
    /// Reuses the original source owner of the caller's two paid material sessions.
    public func prepareIntersectionGraph(facePairs: [BooleanFacePairCandidate],
        classifications: PreparedSolidClassificationPair,
        using execution: inout OriginalQueryExecution) throws -> PreparedBooleanIntersectionGraph {
        let graph = try completeIntersectionGraph(facePairs: facePairs,
            validatedModel: classifications.validatedModel, using: &execution)
        try Task.checkCancellation()
        try execution.consumeWork(1)
        return PreparedBooleanIntersectionGraph(graph: graph,
            validatedModel: classifications.validatedModel, targetBodyIDs: [], toolBodyID: nil,
            classifications: classifications)
    }

    /// Captures authored finite-face identities without fabricating Boolean body operands.
    public func prepareIntersectionGraph(facePairs: [BooleanFacePairCandidate],
        validatedModel: ValidatedBRepModel,
        using execution: inout OriginalQueryExecution) throws -> PreparedBooleanIntersectionGraph {
        let graph = try completeIntersectionGraph(facePairs: facePairs,
            validatedModel: validatedModel, using: &execution)
        try Task.checkCancellation()
        try execution.consumeWork(1)
        return PreparedBooleanIntersectionGraph(graph: graph, validatedModel: validatedModel,
            targetBodyIDs: [], toolBodyID: nil)
    }

    /// Captures source binding at the original producer, without a caller graph substitution.
    public func prepareIntersectionGraph(targetBodyIDs: [BodyID], toolBodyID: BodyID,
        operation: BooleanOperation, validatedModel: ValidatedBRepModel,
        using execution: inout OriginalQueryExecution) throws -> PreparedBooleanIntersectionGraph {
        let graph = try completeIntersectionGraph(targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID, operation: operation, validatedModel: validatedModel, using: &execution)
        try Task.checkCancellation()
        try execution.consumeWork(1)
        return PreparedBooleanIntersectionGraph(graph: graph, validatedModel: validatedModel,
            targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID)
    }
}
