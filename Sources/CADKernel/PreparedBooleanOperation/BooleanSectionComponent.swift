import CADCore

/// Complete section correspondence, including transverse curves, tangent points and common supports.
public struct BooleanSectionComponent: Sendable, Hashable {
    public let facePair: BooleanFacePairCandidate
    public let componentID: BooleanFaceSplitComponentID
    public let geometry: BooleanFaceSplitComponentGeometry

    public init(facePair: BooleanFacePairCandidate, componentID: BooleanFaceSplitComponentID,
                geometry: BooleanFaceSplitComponentGeometry) {
        self.facePair = facePair
        self.componentID = componentID
        self.geometry = geometry
    }
}
