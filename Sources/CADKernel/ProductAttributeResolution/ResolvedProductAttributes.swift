import CADCore
import CADIR

public struct ResolvedProductAttributes: Sendable {
    public let documentID: DocumentID
    public let values: [ResolvedProductTarget: ResolvedProductProperties]
    /// Runtime local topology for source geometry targets; never persisted as attribute authority.
    public let localGeometry: [ProductAttributeTarget: TopologyReference]
    public let consumedWork: Int
    public init(documentID: DocumentID, values: [ResolvedProductTarget: ResolvedProductProperties],
                localGeometry: [ProductAttributeTarget: TopologyReference], consumedWork: Int) {
        self.documentID = documentID; self.values = values; self.localGeometry = localGeometry; self.consumedWork = consumedWork
    }
}
