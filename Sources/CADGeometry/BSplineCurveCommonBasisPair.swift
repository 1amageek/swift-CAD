public struct BSplineCurveCommonBasisPair: Sendable, Hashable {
    public let first: BSplineCurve3D
    public let second: BSplineCurve3D

    public init(first: BSplineCurve3D, second: BSplineCurve3D) {
        self.first = first
        self.second = second
    }
}
