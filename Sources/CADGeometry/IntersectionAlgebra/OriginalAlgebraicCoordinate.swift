/// A retained exact cell sample; it never represents the whole cell's range.
public struct OriginalAlgebraicCoordinate: Sendable {
    public struct Enclosure: Sendable {
        public let lower: ExactRationalCoefficient
        public let upper: ExactRationalCoefficient
        public let sourceDepth: Int
        package let retained: OriginalSingularFieldValueIsolation

        /// Refines the same original value while preserving its causal depth.
        public func refined(maximumWidth: ExactRationalCoefficient, maximumDepth: Int,
            usage: OriginalRelationUsage) throws -> Self {
            var admission = usage
            try intersectionAlgebraStep(&admission)
            return try Self(retained.refined(maximumWidth: maximumWidth,
                maximumDepth: maximumDepth, usage: &admission))
        }
        private init(_ retained: OriginalSingularFieldValueIsolation) {
            self.retained = retained; lower = retained.lower; upper = retained.upper; sourceDepth = retained.sourceDepth
        }
        package init(original: OriginalSingularFieldElement, inheritedDepth: Int,
            maximumDepth: Int, usage: inout OriginalRelationUsage) throws {
            self.init(try .init(original: original, inheritedDepth: inheritedDepth,
                maximumDepth: maximumDepth, usage: &usage))
        }
    }
    package let original: OriginalSingularFieldElement
    package let inheritedDepth: Int

    public func enclosed(maximumDepth: Int, usage: OriginalRelationUsage) throws -> Enclosure {
        var admission = usage
        try intersectionAlgebraStep(&admission)
        return try Enclosure(original: original, inheritedDepth: inheritedDepth,
            maximumDepth: maximumDepth, usage: &admission)
    }
}
