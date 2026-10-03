import CADIR

public struct ResolvedProductProperties: Sendable, Equatable {
    public let properties: [ProductAttributeValue.Property: ResolvedProductProperty]
    public let layers: Set<ProductLayerID>
    public let sourceName: String?
    public init(properties: [ProductAttributeValue.Property: ResolvedProductProperty], layers: Set<ProductLayerID>, sourceName: String? = nil) {
        self.properties = properties; self.layers = layers; self.sourceName = sourceName
    }
}
