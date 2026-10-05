import CADGeometry

/// A complete original pair partition bound to indices of the retained source array.
public struct OriginalPlanarContourPairContact: Sendable {
    public let firstSegmentIndex: Int
    public let secondSegmentIndex: Int
    public let partition: OriginalPlanarCurveContactPartition

    package init(firstSegmentIndex: Int, secondSegmentIndex: Int,
        partition: OriginalPlanarCurveContactPartition) {
        self.firstSegmentIndex = firstSegmentIndex; self.secondSegmentIndex = secondSegmentIndex
        self.partition = partition
    }
}
