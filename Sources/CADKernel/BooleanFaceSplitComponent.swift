public struct BooleanFaceSplitComponent: Hashable, Sendable {
    public let id: BooleanFaceSplitComponentID
    public let geometry: BooleanFaceSplitComponentGeometry

    public init(
        id: BooleanFaceSplitComponentID,
        geometry: BooleanFaceSplitComponentGeometry
    ) {
        self.id = id
        self.geometry = geometry
    }
}

#if !hasFeature(Embedded)
extension BooleanFaceSplitComponent: Codable {}
#endif
