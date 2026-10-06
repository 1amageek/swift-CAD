/// Links a merged source cut back to a complete original pair event partition.
public struct OriginalPlanarContourEndpointReference: Sendable {
    public let pairIndex: Int
    public let secondSource: Bool
    public let cutIndex: Int

    package init(pairIndex: Int, secondSource: Bool, cutIndex: Int) {
        self.pairIndex = pairIndex; self.secondSource = secondSource; self.cutIndex = cutIndex
    }
}
