public struct BooleanFaceSplit: Codable, Hashable, Sendable {
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
