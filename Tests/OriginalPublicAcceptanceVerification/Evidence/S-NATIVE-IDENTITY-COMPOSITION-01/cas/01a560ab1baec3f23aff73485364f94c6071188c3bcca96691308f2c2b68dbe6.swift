import CADCore

public enum TopologyRetentionIssue: Sendable, Equatable {
    case tableIdentityMismatch(key: TopologyEntityReference, stored: TopologyEntityReference)
    case missingReference(owner: TopologyEntityReference?, target: TopologyEntityReference)
    case duplicateReference(owner: TopologyEntityReference, child: TopologyEntityReference)
    case multipleOwners(child: TopologyEntityReference, owners: [TopologyEntityReference])
    case excessiveEdgeIncidence(edgeID: EdgeID, useCount: Int)
    case nonManifoldVertexLink(vertexID: VertexID, componentCount: Int, branchCount: Int)
    case brokenLoop(loopID: LoopID, coedgeIndex: Int)
    case branchingWire(vertexID: VertexID, degree: Int, rootVisit: Int)
    case branchingLooseEdges(vertexID: VertexID, degree: Int)
    case brokenWire(rootVisit: Int, edgeIndex: Int)
    case incompatibleSolidRoot(BodyID)
    case emptyChildren(TopologyEntityReference)
    case emptyCompound(rootVisit: Int)
}
