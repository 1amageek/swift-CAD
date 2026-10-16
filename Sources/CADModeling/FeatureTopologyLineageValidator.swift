import CADCore
import CADGeometry
import CADTopology
import CADIR

package struct FeatureTopologyLineageValidator: Sendable {
    package init() {}

    package func validate(
        _ result: EvaluationResult,
        featureID: FeatureID? = nil
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(result, featureID: featureID, using: &execution)
    }

    package func validate(
        _ result: EvaluationResult,
        featureID: FeatureID? = nil
    , using execution: inout OriginalQueryExecution) throws {
        var outputIDs: Set<SubshapeID> = []
        for id in result.subshapes.keys { try OriginalParameterQueryStorage.insert(id, in: &outputIDs, using: &execution) }
        var lineageIDs: Set<SubshapeID> = []
        for id in result.lineage.keys { try OriginalParameterQueryStorage.insert(id, in: &lineageIDs, using: &execution) }
        try execution.retainStorage(count: outputIDs.count, stride: MemoryLayout<SubshapeID>.stride)
        try execution.retainStorage(count: lineageIDs.count, stride: MemoryLayout<SubshapeID>.stride)
        if let featureID,
           let foreignOutput = outputIDs.sorted().first(where: {
               $0.featureID != featureID
           }) {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                featureID: featureID,
                subshapeID: foreignOutput,
                tolerance: nil,
                message: "Feature topology output must be owned by the evaluating feature."
            )
        }
        guard outputIDs == lineageIDs else {
            var mismatchedID: SubshapeID?
            for id in outputIDs {
                try execution.consumeWork(1)
                if !lineageIDs.contains(id), mismatchedID.map({ id < $0 }) ?? true { mismatchedID = id }
            }
            for id in lineageIDs {
                try execution.consumeWork(1)
                if !outputIDs.contains(id), mismatchedID.map({ id < $0 }) ?? true { mismatchedID = id }
            }
            throw failure(
                subshapeID: mismatchedID,
                message: "Feature topology outputs and lineage entries must have one-to-one coverage."
            )
        }

        var parentUseCount: [SubshapeID: Int] = [:]
        var splitParents = Set<SubshapeID>()
        for outputID in lineageIDs.sorted() {
            try execution.consumeWork(1)
            guard let entry = result.lineage[outputID],
                  entry.output == outputID,
                  entry.isStructurallyValid else {
                throw failure(
                    subshapeID: outputID,
                    message: "Feature topology lineage entry is structurally invalid."
                )
            }
            for parent in entry.parents {
                try execution.consumeWork(1)
                let next = parentUseCount[parent, default: 0].addingReportingOverflow(1)
                guard !next.overflow else { throw ExactScalarFailure.countOverflow }
                try OriginalParameterQueryStorage.set(next.partialValue, for: parent, in: &parentUseCount, using: &execution)
            }
            if entry.relation == .split, let parent = entry.parents.first {
                try OriginalParameterQueryStorage.insert(parent, in: &splitParents, using: &execution)
            }
        }
        if let invalidSplit = splitParents.first(where: {
            parentUseCount[$0, default: 0] < 2
        }) {
            throw failure(
                subshapeID: invalidSplit,
                message: "Split topology lineage requires at least two outputs from the same parent."
            )
        }
    }

    private func failure(
        subshapeID: SubshapeID?,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .topologyFailure,
            featureID: subshapeID?.featureID,
            subshapeID: subshapeID,
            tolerance: nil,
            message: message
        )
    }
}
