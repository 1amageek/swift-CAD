import CADCore
import CADIR

package struct FeatureTopologyLineageValidator: Sendable {
    package init() {}

    package func validate(
        _ result: EvaluationResult,
        featureID: FeatureID? = nil
    ) throws {
        let outputIDs = Set(result.subshapes.keys)
        let lineageIDs = Set(result.lineage.keys)
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
            let mismatchedID = outputIDs.symmetricDifference(lineageIDs).sorted().first
            throw failure(
                subshapeID: mismatchedID,
                message: "Feature topology outputs and lineage entries must have one-to-one coverage."
            )
        }

        var parentUseCount: [SubshapeID: Int] = [:]
        var splitParents = Set<SubshapeID>()
        for outputID in lineageIDs.sorted() {
            guard let entry = result.lineage[outputID],
                  entry.output == outputID,
                  entry.isStructurallyValid else {
                throw failure(
                    subshapeID: outputID,
                    message: "Feature topology lineage entry is structurally invalid."
                )
            }
            for parent in entry.parents {
                parentUseCount[parent, default: 0] += 1
            }
            if entry.relation == .split, let parent = entry.parents.first {
                splitParents.insert(parent)
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
