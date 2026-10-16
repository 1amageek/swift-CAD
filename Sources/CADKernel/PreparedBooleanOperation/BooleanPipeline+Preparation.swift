import CADCore
import CADGeometry
import CADTopology

public extension BooleanPipeline {
    func prepare(targetBodyIDs: [BodyID], toolBodyID: BodyID, model: BRepModel,
                 policy: BooleanPreparationPolicy = BooleanPreparationPolicy(),
                 tolerance: ModelingTolerance) throws -> PreparedBooleanIntersection {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try prepare(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID, model: model,
            policy: policy, tolerance: tolerance, using: &execution)
    }

    func prepare(targetBodyIDs: [BodyID], toolBodyID: BodyID, model: BRepModel,
                 policy: BooleanPreparationPolicy = BooleanPreparationPolicy(),
                 tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
                 throws -> PreparedBooleanIntersection {
        do {
            let effective = try policy.effectiveTolerance(from: tolerance)
            let prepared = try execution.withPreparationScope { execution in
                let graph = try completeIntersectionGraph(targetBodyIDs: targetBodyIDs,
                    toolBodyID: toolBodyID, operation: .union, model: model,
                    tolerance: effective, using: &execution)
                let split = try uvSplitGraph(intersectionGraph: graph, model: model,
                    tolerance: effective, using: &execution)
                try split.validate(intersectionGraph: graph, model: model,
                    tolerance: effective, using: &execution)
                return (graph: graph, split: split)
            }
            return try retainedPreparation(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID,
                model: model, policy: policy, tolerance: effective, sourceTolerance: tolerance,
                graph: prepared.result.graph, split: prepared.result.split, depth: prepared.depth,
                using: &execution)
        } catch {
            throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
        }
    }

    private func retainedPreparation(targetBodyIDs: [BodyID], toolBodyID: BodyID, model: BRepModel,
        policy: BooleanPreparationPolicy, tolerance: ModelingTolerance, sourceTolerance: ModelingTolerance,
        graph: BooleanIntersectionGraph, split: BooleanUVSplitGraph, depth: OriginalQueryPreparationDepth,
        using execution: inout OriginalQueryExecution) throws -> PreparedBooleanIntersection {
        let lifetime = try PreparedBooleanQueryLifetime.retain(depth: depth, using: &execution)
        let result = PreparedBooleanIntersection(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID,
            tolerance: tolerance, sourceTolerance: sourceTolerance, policy: policy,
            model: model, pipeline: self, intersectionGraph: graph, uvSplitGraph: split, lifetime: lifetime)
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
    }

    /// Computes independent target/tool pairs concurrently and combines them in target input order.
    func prepareConcurrently(targetBodyIDs: [BodyID], toolBodyID: BodyID, model: BRepModel,
                             policy: BooleanPreparationPolicy = BooleanPreparationPolicy(),
                             tolerance: ModelingTolerance) async throws -> PreparedBooleanIntersection {
        var execution = try OriginalQueryExecution.kernelOriginal()
        let budget = execution.budget, limits = execution.limits, context = execution.context
        let effective = try policy.effectiveTolerance(from: tolerance)
        guard !targetBodyIDs.isEmpty, Set(targetBodyIDs).count == targetBodyIDs.count,
              !targetBodyIDs.contains(toolBodyID) else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: effective,
                message: "Boolean preparation requires distinct targets and a separate tool.")
        }
        let graphs = try await withThrowingTaskGroup(of: (Int, BooleanIntersectionGraph, OriginalQueryPreparationDepth).self) { group in
            for (ordinal, target) in targetBodyIDs.enumerated() {
                group.addTask {
                    try CurrentTaskCancellationChecker().checkCancellation()
                    var child = OriginalQueryExecution(budget: budget, limits: limits, context: context)
                    let prepared = try child.withPreparationScope { execution in
                        try self.completeIntersectionGraph(targetBodyIDs: [target], toolBodyID: toolBodyID,
                            operation: .union, model: model, tolerance: effective, using: &execution)
                    }
                    return (ordinal, prepared.result, prepared.depth)
                }
            }
            var results: [(Int, BooleanIntersectionGraph, OriginalQueryPreparationDepth)] = []
            for try await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        let prepared = try execution.withPreparationScope { execution in
            for child in graphs {
                try execution.admitDepth(value: child.2.scalar.value, coefficient: child.2.scalar.coefficient)
                try execution.admitSourceDepth(child.2.sourceDepth)
                try execution.admitGeometricDepth(child.2.geometricDepth)
                try execution.admitTransportDepth(child.2.transportDepth)
            }
            let graph = BooleanIntersectionGraph(facePairs: graphs.flatMap { $0.1.facePairs },
                boundaryContacts: graphs.flatMap { $0.1.boundaryContacts },
                faceIntersections: graphs.flatMap { $0.1.faceIntersections })
            // The shared contact registry sees all target graphs before clipping.
            let split = try uvSplitGraph(intersectionGraph: graph, model: model,
                tolerance: effective, using: &execution)
            try graph.validate(in: model, tolerance: effective, using: &execution)
            try split.validate(intersectionGraph: graph, model: model,
                tolerance: effective, using: &execution)
            return (graph: graph, split: split)
        }
        return try retainedPreparation(targetBodyIDs: targetBodyIDs, toolBodyID: toolBodyID,
            model: model, policy: policy, tolerance: effective, sourceTolerance: tolerance,
            graph: prepared.result.graph, split: prepared.result.split, depth: prepared.depth,
            using: &execution)
    }
}
