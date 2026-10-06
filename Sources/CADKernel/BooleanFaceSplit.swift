public struct BooleanFaceSplit: Hashable, Sendable {
    public let facePair: BooleanFacePairCandidate
    public let components: [BooleanFaceSplitComponent]

    public init(
        facePair: BooleanFacePairCandidate,
        components: [BooleanFaceSplitComponent]
    ) {
        self.facePair = facePair
        self.components = components
    }
}

#if !hasFeature(Embedded)
extension BooleanFaceSplit: Codable {}
#endif
