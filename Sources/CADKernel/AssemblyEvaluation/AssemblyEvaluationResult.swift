import CADCore
import CADIR
import CADTopology

public struct AssemblyEvaluationResult: Sendable {
    public let model: BRepModel
    public let subshapes: SubshapeIndex
    public let lineage: [SubshapeID: TopologyLineage]
    public let artifact: AssemblyEvaluationArtifact
    public let consumedWork: Int
    public init(model: BRepModel, subshapes: SubshapeIndex,
                lineage: [SubshapeID: TopologyLineage], artifact: AssemblyEvaluationArtifact, consumedWork: Int) {
        self.model = model; self.subshapes = subshapes; self.lineage = lineage; self.artifact = artifact
        self.consumedWork = consumedWork
    }
}
