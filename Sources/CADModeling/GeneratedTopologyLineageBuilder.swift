import CADCore
import CADGeometry
import CADIR

public struct GeneratedTopologyLineageBuilder: Sendable {
    public init() {}

    public func build(featureID: FeatureID, subshapes: [SubshapeID: TopologyReference]) throws -> [SubshapeID: TopologyLineage] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try build(featureID: featureID, subshapes: subshapes, using: &execution)
    }

    public func build(
        featureID: FeatureID,
        subshapes: [SubshapeID: TopologyReference], using execution: inout OriginalQueryExecution
    ) throws -> [SubshapeID: TopologyLineage] {
        try execution.retainStorage(count: subshapes.count,
            stride: MemoryLayout<(SubshapeID, TopologyLineage)>.stride)
        try execution.retainStorage(count: subshapes.count, stride: MemoryLayout<SubshapeID>.stride)
        var result: [SubshapeID: TopologyLineage] = [:]
        result.reserveCapacity(subshapes.count)
        let ordered = try subshapes.keys.sorted { first, second in
            try execution.consumeWork(1)
            return first < second
        }
        for output in ordered {
            try execution.consumeWork(1)
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
