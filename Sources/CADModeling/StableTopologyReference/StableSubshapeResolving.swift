import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Resolves a persistent subshape selection against live topology and lineage.
public protocol StableSubshapeResolving: Sendable {
    func topologyReference(
        for reference: StableSubshapeReference,
        model: BRepModel,
        subshapes: SubshapeIndex,
        lineage: [SubshapeID: TopologyLineage],
        tolerance: ModelingTolerance
    ) throws -> TopologyReference
    func topologyReference(for reference: StableSubshapeReference, model: BRepModel,
        subshapes: SubshapeIndex, lineage: [SubshapeID: TopologyLineage],
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, using execution: inout OriginalQueryExecution) throws -> TopologyReference
}
