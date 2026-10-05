import CADCore
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
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?,
        maximumAlgebraicDepth: Int = 32) throws -> PreparedBooleanIntersectionGraph {
        let graph = try completeIntersectionGraph(facePairs: facePairs,
            validatedModel: classifications.validatedModel, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        try Task.checkCancellation()
        try consumeWork(0)
        return PreparedBooleanIntersectionGraph(graph: graph,
            validatedModel: classifications.validatedModel, targetBodyIDs: [], toolBodyID: nil,
            classifications: classifications)
    }

    /// Captures authored finite-face identities without fabricating Boolean body operands.
    public func prepareIntersectionGraph(facePairs: [BooleanFacePairCandidate],
        validatedModel: ValidatedBRepModel,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?,
        maximumAlgebraicDepth: Int = 32) throws -> PreparedBooleanIntersectionGraph {
        let graph = try completeIntersectionGraph(facePairs: facePairs,
            validatedModel: validatedModel, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        try Task.checkCancellation()
        try consumeWork(0)
        return PreparedBooleanIntersectionGraph(graph: graph, validatedModel: validatedModel,
            targetBodyIDs: [], toolBodyID: nil)
    }

    /// Captures source binding at the original producer, without a caller graph substitution.
    public func prepareIntersectionGraph(targetBodyIDs: [BodyID], toolBodyID: BodyID,
        operation: BooleanOperation, validatedModel: ValidatedBRepModel,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?,
        maximumAlgebraicDepth: Int = 32) throws -> PreparedBooleanIntersectionGraph {
        let graph = try completeIntersectionGraph(targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID, operation: operation, validatedModel: validatedModel,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
            consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        try Task.checkCancellation()
        try consumeWork(0)
        return PreparedBooleanIntersectionGraph(graph: graph, validatedModel: validatedModel,
            targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID)
    }
}
