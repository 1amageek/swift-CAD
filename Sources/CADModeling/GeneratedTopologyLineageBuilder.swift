import CADCore
import CADIR

public struct GeneratedTopologyLineageBuilder: Sendable {
    public init() {}

    public func build(
        featureID: FeatureID,
        subshapes: [SubshapeID: TopologyReference]
    ) throws -> [SubshapeID: TopologyLineage] {
        var result: [SubshapeID: TopologyLineage] = [:]
        result.reserveCapacity(subshapes.count)
        for output in subshapes.keys.sorted() {
            guard output.featureID == featureID else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    featureID: featureID,
                    subshapeID: output,
                    tolerance: nil,
                    message: "Generated topology identity must belong to the evaluating feature."
                )
            }
            result[output] = TopologyLineage(output: output, relation: .generated)
        }
        return result
    }
}
