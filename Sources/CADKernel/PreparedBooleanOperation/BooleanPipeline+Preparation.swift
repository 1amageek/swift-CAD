import CADCore
import CADTopology

public extension BooleanPipeline {
    func prepare(targetBodyIDs: [BodyID], toolBodyID: BodyID, model: BRepModel,
                 policy: BooleanPreparationPolicy = BooleanPreparationPolicy(),
                 tolerance: ModelingTolerance) throws -> PreparedBooleanIntersection {
        try CurrentTaskCancellationChecker().checkCancellation()
        let effective = try policy.effectiveTolerance(from: tolerance)
        let graph = try completeIntersectionGraph(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID,
            operation: .union, model: model, tolerance: effective)
        try CurrentTaskCancellationChecker().checkCancellation()
        let split = try uvSplitGraph(intersectionGraph: graph, model: model, tolerance: effective)
        try split.validate(intersectionGraph: graph, model: model, tolerance: effective)
        try CurrentTaskCancellationChecker().checkCancellation()
        let prepared = PreparedBooleanIntersection(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID,
            tolerance: effective, sourceTolerance: tolerance, policy: policy,
            model: model, pipeline: self, intersectionGraph: graph, uvSplitGraph: split)
        try CurrentTaskCancellationChecker().checkCancellation()
        return prepared
    }

    /// Computes independent target/tool pairs concurrently and combines them in target input order.
    func prepareConcurrently(targetBodyIDs: [BodyID], toolBodyID: BodyID, model: BRepModel,
                             policy: BooleanPreparationPolicy = BooleanPreparationPolicy(),
                             tolerance: ModelingTolerance) async throws -> PreparedBooleanIntersection {
        let effective = try policy.effectiveTolerance(from: tolerance)
        guard !targetBodyIDs.isEmpty, Set(targetBodyIDs).count == targetBodyIDs.count,
              !targetBodyIDs.contains(toolBodyID) else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: effective,
                message: "Boolean preparation requires distinct targets and a separate tool.")
        }
        let graphs = try await withThrowingTaskGroup(of: (Int, BooleanIntersectionGraph).self) { group in
            for (ordinal, target) in targetBodyIDs.enumerated() {
                group.addTask {
                    try CurrentTaskCancellationChecker().checkCancellation()
                    let graph = try self.completeIntersectionGraph(targetBodyIDs: [target], toolBodyID: toolBodyID,
                        operation: .union, model: model, tolerance: effective)
                    return (ordinal, graph)
                }
            }
            var results: [(Int, BooleanIntersectionGraph)] = []
            for try await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        let graph = BooleanIntersectionGraph(facePairs: graphs.flatMap { $0.facePairs },
            boundaryContacts: graphs.flatMap { $0.boundaryContacts },
            faceIntersections: graphs.flatMap { $0.faceIntersections })
        // Splitting owns a shared physical-curve contact registry. Combine every target
        // graph first so twin spans use the same complete union of subdivision contacts.
        let split = try uvSplitGraph(intersectionGraph: graph, model: model, tolerance: effective)
        try graph.validate(in: model, tolerance: effective)
        try split.validate(intersectionGraph: graph, model: model, tolerance: effective)
        let prepared = PreparedBooleanIntersection(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID,
            tolerance: effective, sourceTolerance: tolerance, policy: policy,
            model: model, pipeline: self, intersectionGraph: graph, uvSplitGraph: split)
        try CurrentTaskCancellationChecker().checkCancellation()
        return prepared
    }
}
