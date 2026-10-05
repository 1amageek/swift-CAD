/// A connected original zero component with original chart adjacency certificates.
public struct SurfaceSilhouetteComponent: Sendable {
    public struct Join: Sendable {
        public enum Kind: Sendable { case continuation, transverseCrossing, tangentContact, cusp, singularIntersection }
        public let kind: Kind
        public let firstCurve: Int
        public let firstAtUpperEnd: Bool
        public let secondCurve: Int
        public let secondAtUpperEnd: Bool
        public let periodic: Bool
        public let branchContactOrder: Int?
        public let originalIntersectionMultiplicity: Int?
    }
    public let curveIndices: [Int]
    public let joins: [Join]
    public let isClosed: Bool

    init(curveIndices: [Int], joins: [Join], isClosed: Bool) {
        self.curveIndices = curveIndices; self.joins = joins; self.isClosed = isClosed
    }
}
