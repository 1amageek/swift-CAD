import CADCore
import CADIR

struct LiveTopologyParentResolver: Sendable {
    func resolve(
        _ reference: TopologyReference,
        in subshapes: SubshapeIndex,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> SubshapeID {
        let candidates = subshapes.entries.compactMap { subshapeID, candidate in
            candidate == reference ? subshapeID : nil
        }.sorted()
        guard let parent = candidates.first else {
            throw KernelError(
                phase: .topology,
                code: .missingReference,
                featureID: featureID,
                tolerance: tolerance,
                message: "Edited topology has no live parent identity."
            )
        }
        guard candidates.count == 1 else {
            throw KernelError(
                phase: .topology,
                code: .ambiguousSelection,
                featureID: featureID,
                subshapeID: parent,
                tolerance: tolerance,
                message: "Edited topology has multiple live parent identities."
            )
        }
        return parent
    }
}
