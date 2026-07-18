import CADCore
import CADIR

package struct CarriedTopologyIdentity: Sendable {
    package let subshapes: [SubshapeID: TopologyReference]
    package let lineage: [SubshapeID: TopologyLineage]

    package init(
        subshapes: [SubshapeID: TopologyReference],
        lineage: [SubshapeID: TopologyLineage]
    ) {
        self.subshapes = subshapes
        self.lineage = lineage
    }
}
