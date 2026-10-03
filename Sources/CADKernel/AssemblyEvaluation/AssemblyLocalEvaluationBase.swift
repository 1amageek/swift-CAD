import CADCore
import CADIR
import CADTopology

/// Immutable local feature evaluation domain retained independently of world copies.
public struct AssemblyLocalEvaluationBase: Codable, Sendable, Equatable {
    public let model: BRepModel
    public let subshapes: SubshapeIndex
    public let lineage: [SubshapeID: TopologyLineage]
    public init(model: BRepModel, subshapes: SubshapeIndex, lineage: [SubshapeID: TopologyLineage]) {
        self.model = model; self.subshapes = subshapes; self.lineage = lineage
    }
}
