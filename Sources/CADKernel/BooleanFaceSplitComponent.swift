public struct BooleanFaceSplitComponent: Codable, Hashable, Sendable {
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
